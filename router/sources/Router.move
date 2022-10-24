module Multichain::Router {
    use std::string;
    use std::error;
    use std::signer;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use aptos_std::type_info;
    use aptos_std::event::{Self,EventHandle};
    use aptos_framework::account;
    use Multichain::Pool;

    struct RouterMintCap<phantom CoinType> has key, store {
        cap: MintCapability<CoinType>,
    }

    struct RouterBurnCap<phantom CoinType> has key, store {
        cap: BurnCapability<CoinType>,
    }

    struct SwapOutEventHolder has key {
        events: EventHandle<SwapOutEvent>,
    }

    struct SwapOutEvent has drop, store {
        token: string::String,
        from: address,
        to: string::String,
        amount: u64,
        to_chain_id: u64
    }

    struct SwapInEventHolder has key {
        events: EventHandle<SwapInEvent>,
    }

    struct SwapInEvent has drop, store {
        tx_hash: string::String,
        token: string::String,
        to: address,
        amount: u64,
        from_chain_id: u64
    }

    struct Status has key {
        open: u8,
    }

    // 0: directly minted token  
    // 1: pool token  
    struct TokenInfo<phantom CoinType> has key {  
        mode: u8,  
    }  

    fun init_module(admin: &signer ) {
        move_to(admin, SwapInEventHolder {
            events: account::new_event_handle<SwapInEvent>(admin)
        });
        move_to(admin, SwapOutEventHolder {
            events: account::new_event_handle<SwapOutEvent>(admin)
        });
        move_to(admin, Status {
            open: 1
        });
    }
  
    public entry fun set_coin<CoinType>(admin: &signer, mode: u8) acquires TokenInfo{ 
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Multichain, error::permission_denied(1));
        if( exists<TokenInfo<CoinType>>(admin_addr) ){
            let token_type = borrow_global_mut<TokenInfo<CoinType>>(admin_addr);  
            token_type.mode = mode
        }else{
            move_to(admin, TokenInfo<CoinType>{mode});  
        }
    }  

    public entry fun set_status(admin: &signer, open: u8) acquires Status { 
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Multichain, error::permission_denied(1));
        let status = borrow_global_mut<Status>(admin_addr);  
        status.open = open
    } 

    // call by other model
    public fun approve_coin<CoinType>(admin: &signer, mint_cap: MintCapability<CoinType>, burn_cap: BurnCapability<CoinType>) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Multichain, error::permission_denied(1));
        move_to(admin, RouterMintCap<CoinType> { cap: mint_cap });
        move_to(admin, RouterBurnCap<CoinType> { cap: burn_cap });
    }

    public entry fun set_poolcoin_cap<CoinType>(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Multichain, error::permission_denied(1));
        if (!exists<RouterMintCap<CoinType>>(admin_addr)){
            let (mint_cap, burn_cap) = Pool::copy_capabilities<CoinType>(admin);
            move_to(admin, RouterMintCap<CoinType> { cap: mint_cap });
            move_to(admin, RouterBurnCap<CoinType> { cap: burn_cap });
        }
    }

    public entry fun swapout<CoinType>(account: &signer, amount: u64, _receiver: string::String, _toChainID: u64) 
        acquires Status,RouterBurnCap, TokenInfo, SwapOutEventHolder {  
        check_status();
        let type_info = type_info::type_of<TokenInfo<CoinType>>();
        let admin_addr = type_info::account_address(&type_info);
        assert!(
            exists<TokenInfo<CoinType>>(admin_addr),
            error::unavailable(1),
        );
        let signer_address = signer::address_of(account);
        let tokenInfo = borrow_global<TokenInfo<CoinType>>(admin_addr);  
        if (tokenInfo.mode == 1) { 
            // CoinType is UnderlyingCoin, not PoolCoin
            let coin = coin::withdraw<CoinType>(account, amount);
            Pool::depositByVault<CoinType>(coin);
        }else{
            let burn_cap = borrow_global<RouterBurnCap<CoinType>>(admin_addr);
            coin::burn_from<CoinType>(signer_address, amount, &burn_cap.cap);
        };
        let event_holder = borrow_global_mut<SwapOutEventHolder>(admin_addr);
        event::emit_event(&mut event_holder.events, SwapOutEvent {
            token: type_info::type_name<CoinType>(),
            from: signer_address,
            to: _receiver,
            amount: amount,
            to_chain_id: _toChainID
        });
    } 

    public entry fun swapin<CoinType, PoolCoin>(admin: &signer, receiver: address, amount: u64, _fromEvent: string::String, _fromChainID: u64) 
        acquires Status,RouterMintCap,TokenInfo,SwapInEventHolder {   
        check_status();
        let type_info = type_info::type_of<TokenInfo<CoinType>>();
        let admin_addr = type_info::account_address(&type_info);
        assert!(admin_addr == signer::address_of(admin), error::permission_denied(1));

        let tokenInfo = borrow_global<TokenInfo<CoinType>>(admin_addr);  
        if (tokenInfo.mode == 1) { 
            // CoinType is UnderlyingCoin
            let vaultAmount = Pool::vault<CoinType>(admin);
            // mint anyToken if UnderlyingCoin is not enough
            if(vaultAmount < amount){
                Pool::mint_poolcoin<CoinType, PoolCoin>(admin, receiver,amount);
            }else{
                let coin = Pool::withdrawByVault<CoinType>(admin, amount);
                coin::deposit<CoinType>(receiver, coin);
            }
        }else{
            let mint_cap = borrow_global<RouterMintCap<CoinType>>(admin_addr);
            let coins_minted = coin::mint<CoinType>(amount, &mint_cap.cap);
            coin::deposit<CoinType>(receiver, coins_minted);
        };
       let event_holder = borrow_global_mut<SwapInEventHolder>(admin_addr);
        event::emit_event(&mut event_holder.events, SwapInEvent {
            tx_hash: _fromEvent,
            token: type_info::type_name<CoinType>(),
            to: receiver,
            amount: amount,
            from_chain_id: _fromChainID
        });
    }

    fun check_status() acquires Status{
        let status = borrow_global<Status>(@Multichain);
        assert!(status.open == 1, error::unavailable(502));
    }
}
