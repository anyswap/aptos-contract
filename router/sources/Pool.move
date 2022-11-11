/// This module provides the foundation for multichain anyCoin
module Multichain::Pool { 
    use std::string;   
    use std::signer; 
    use std::error;
    use std::vector;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability, FreezeCapability}; 
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_std::table::{Self, Table};

    // friend Multichain::Router;

    // store key: PoolCoin TypeInfo value: UnderlyingCoin TypeInfo
    struct PoolCoinMap has key{
        t : Table<TypeInfo, TypeInfo>
    }
     // store key: UnderlyingCoin TypeInfo TypeInfo value: PoolCoin TypeInfo
    struct UnderlyingCoinMap has key{
        t : Table<TypeInfo, TypeInfo>
    }

    struct Vault<phantom UnderlyingCoinType> has key, store {
        coin: coin::Coin<UnderlyingCoinType>,
    } 

    struct Capabilities<phantom PoolCoinType> has key {
        mint_cap: MintCapability<PoolCoinType>,
        freeze_cap: FreezeCapability<PoolCoinType>,
        burn_cap: BurnCapability<PoolCoinType>,
    }

    fun init_module( admin: &signer ) {
        move_to(admin, PoolCoinMap {
            t: table::new(),
        });
        move_to(admin, UnderlyingCoinMap {
            t: table::new(),
        });
        move_to(admin, PoolPairs {
            list: vector::empty<string::String>(),
        });
    }

    public entry fun register_coin<UnderlyingCoinType, PoolCoinType>(admin: &signer, name: string::String, symbol: string::String, decimals: u8) 
        acquires PoolCoinMap,UnderlyingCoinMap,PoolPairs {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Multichain, error::permission_denied(1));
        assert!(
            !exists<Vault<UnderlyingCoinType>>(admin_addr),
            error::already_exists(2),
        );

        assert!(coin::is_coin_initialized<UnderlyingCoinType>(), error::not_found(3));

        let pc_type_info = type_info::type_of<PoolCoinType>();
        let pc_address = type_info::account_address(&pc_type_info);
        assert!(
            pc_address == admin_addr,
            error::permission_denied(4),
        );

        let vault = Vault<UnderlyingCoinType> {
            coin: coin::zero<UnderlyingCoinType>(),
        };
        move_to(admin, vault);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolCoinType>(
            admin,
            name,
            symbol,
            decimals, 
            false, 
        );
        move_to(admin, Capabilities<PoolCoinType> { mint_cap,freeze_cap, burn_cap } );

        let underlying_type_info = type_info::type_of<UnderlyingCoinType>();

        let pc_map = borrow_global_mut<PoolCoinMap>(admin_addr);
        table::add(&mut pc_map.t, pc_type_info, underlying_type_info);

        let underlying_map = borrow_global_mut<UnderlyingCoinMap>(admin_addr);
        table::add(&mut underlying_map.t, underlying_type_info, pc_type_info);

        if (!exists<PoolPairs>(admin_addr)){
            move_to(admin, PoolPairs {
                list: vector::empty<string::String>(),
            });
        };
        let pool_pairs = borrow_global_mut<PoolPairs>(admin_addr);

        let pairs = type_info::type_name<PoolCoinType>();
        string::append(&mut pairs, string::utf8(b","));
        string::append(&mut pairs, type_info::type_name<UnderlyingCoinType>());

        vector::push_back<string::String>(&mut pool_pairs.list, pairs);
    }

    // add liquidity with underlying token
    public entry fun deposit<UnderlyingCoinType, PoolCoinType>(account: &signer, amount: u64) acquires UnderlyingCoinMap, Vault, Capabilities {  
        check_coin_type<UnderlyingCoinType, PoolCoinType>();

        // deposit underlying token  
        let vault_coin = &mut borrow_global_mut<Vault<UnderlyingCoinType>>(@Multichain).coin;  
        let deposit_coin = coin::withdraw<UnderlyingCoinType>(account, amount);
        coin::merge<UnderlyingCoinType>(vault_coin, deposit_coin);
  
        // mint pool token  
        let cap = borrow_global<Capabilities<PoolCoinType>>(@Multichain);  
        let coins_minted = coin::mint<PoolCoinType>(amount, &cap.mint_cap); 
        coin::deposit<PoolCoinType>(signer::address_of(account), coins_minted); 
    } 
    // 
    public entry fun withdraw<PoolCoinType, UnderlyingCoinType>(account: &signer, amount: u64) acquires UnderlyingCoinMap, Vault, Capabilities {  
        check_coin_type<UnderlyingCoinType, PoolCoinType>();
        // burn pool token
        let cap = borrow_global<Capabilities<PoolCoinType>>(@Multichain);  
        let coins_burned = coin::withdraw(account, amount);
        coin::burn(coins_burned, &cap.burn_cap);

        // withdraw underlying token  
        let vault_coin = &mut borrow_global_mut<Vault<UnderlyingCoinType>>(@Multichain).coin;  
        let withdraw_coin = coin::extract(vault_coin, amount);
        coin::deposit<UnderlyingCoinType>(signer::address_of(account), withdraw_coin);
    }

    // liquidity providers should not use this function, or coin will get lost
    public fun depositByVault<CoinType>(deposit_coin: coin::Coin<CoinType>) acquires Vault {  
        let type_info = type_info::type_of<Vault<CoinType>>();
        let vault_address = type_info::account_address(&type_info);
        
        // deposit underlying token  
        let vault_coin = &mut borrow_global_mut<Vault<CoinType>>(vault_address).coin;  
        coin::merge<CoinType>(vault_coin, deposit_coin);
    }
 
    public fun withdrawByVault<CoinType>(account: &signer, amount: u64): coin::Coin<CoinType> acquires Vault {  
        let type_info = type_info::type_of<Vault<CoinType>>();
        let vault_address = type_info::account_address(&type_info);

        assert!(
            signer::address_of(account) == vault_address,
            error::permission_denied(2),
        );

        // withdraw underlying token  
        let vault_coin = &mut borrow_global_mut<Vault<CoinType>>(vault_address).coin;  
        coin::extract(vault_coin, amount)
    }

    public fun vault<CoinType>(account: &signer): u64 acquires Vault{  
        let type_info = type_info::type_of<Vault<CoinType>>();
        let vault_address = type_info::account_address(&type_info);

        assert!(
            signer::address_of(account) == vault_address,
            error::permission_denied(2),
        );
        let value = coin::value(&borrow_global<Vault<CoinType>>(vault_address).coin);  
        value
    } 
    
    // return mint/burn capabilities 
    public fun copy_capabilities<CoinType>(account: &signer): (MintCapability<CoinType>, BurnCapability<CoinType>) acquires Capabilities {  
        let type_info = type_info::type_of<CoinType>();
        let vault_address = type_info::account_address(&type_info);

        assert!(
            signer::address_of(account) == vault_address,
            error::permission_denied(1),
        );
        let cap = borrow_global<Capabilities<CoinType>>(@Multichain);
        (cap.mint_cap, cap.burn_cap)
    } 

    public fun mint_poolcoin<UnderlyingCoinType, PoolCoinType>(account: &signer, receiver: address, amount: u64) acquires UnderlyingCoinMap,  Capabilities {  
        assert!(signer::address_of(account) == @Multichain, error::permission_denied(0));
        check_coin_type<UnderlyingCoinType, PoolCoinType>();
        // mint pool token  
        let cap = borrow_global<Capabilities<PoolCoinType>>(@Multichain);  
        let coins_minted = coin::mint<PoolCoinType>(amount, &cap.mint_cap); 
        coin::deposit<PoolCoinType>(receiver, coins_minted); 
    }

     public fun burn_poolcoin<UnderlyingCoinType, PoolCoinType>(account: &signer, from: address, amount: u64) acquires UnderlyingCoinMap,  Capabilities {  
        assert!(signer::address_of(account) == @Multichain, error::permission_denied(0));
        check_coin_type<UnderlyingCoinType, PoolCoinType>();
        // mint pool token  
        let cap = borrow_global<Capabilities<PoolCoinType>>(@Multichain);  
        coin::burn_from<PoolCoinType>(from, amount, &cap.burn_cap);
    }
    
    fun check_coin_type<UnderlyingCoinType, PoolCoinType>() acquires UnderlyingCoinMap{
        let type_info = type_info::type_of<UnderlyingCoinType>();

        let map = borrow_global<UnderlyingCoinMap>(@Multichain);
        assert!(table::contains(&map.t, type_info), error::not_found(404));

        let poolcoin_type = table::borrow(&map.t, type_info);
        let pc_type_info = type_info::type_of<PoolCoinType>();
        assert!(poolcoin_type == &pc_type_info, error::not_found(404));
    }

    struct PoolPairs has key{
        list : vector<string::String>
    }
}