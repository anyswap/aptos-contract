/// The module to show how to create a new coin on Aptos network.
module Multichain::USDC {
    use std::string;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use std::signer;
    use std::error;
    use Multichain::Router;
    
    // Errors.

    /// When capability is missed on account.
    const ERR_CAP_MISSED: u64 = 100;

    /// When capability already exists on account.
    const ERR_CAP_EXISTS: u64 = 101;

    /// Represents new user coin.
    /// Indeeed this type will be used as CoinType for your new coin.
    struct Coin has key {}

    /// The struct to store capability: mint and burn.
    struct Capability<CapType: store> has key {
        cap: CapType
    }
 
    /// Initialize this module: Initializing struct Coin
    fun init_module(account: &signer) {
       initialize_internal(account)
    }

    /// Initializing `Coin` as coin in Aptos network.
    fun initialize_internal(account: &signer) {
          // Initialize `Coin` as coin type using Aptos Framework.
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<Coin>(
            account,
            string::utf8(b"USDC"), 
            string::utf8(b"USDC"),
            18,
            true,
        );

        // Store mint and burn capabilities under user account.
        move_to(account, Capability { cap: mint_cap });
        move_to(account, Capability { cap: burn_cap });
        move_to(account, Capability { cap: freeze_cap });
    }

    // mint
    public entry fun mint(
        account: &signer,
        dst_addr: address,
        amount: u64,
    ) acquires Capability {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Capability<MintCapability<Coin>>>(account_addr),
            error::not_found(0),
        );
        let capabilities = borrow_global<Capability<MintCapability<Coin>>>(account_addr);
        let coins_minted = coin::mint(amount, &capabilities.cap);
        coin::deposit(dst_addr, coins_minted);
    }

    public entry fun burn(
        account: &signer,
        amount: u64,
    ) acquires Capability {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Capability<BurnCapability<Coin>>>(account_addr),
            error::not_found(0),
        );
        let capabilities = borrow_global<Capability<BurnCapability<Coin>>>(account_addr);
        let to_burn = coin::withdraw<Coin>(account, amount);
        coin::burn(to_burn, &capabilities.cap);
    }

    public entry fun copy_cap(
        account: &signer,
    ) acquires Capability {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Capability<MintCapability<Coin>>>(account_addr),
            error::not_found(0),
        );
         assert!(
            exists<Capability<BurnCapability<Coin>>>(account_addr),
            error::not_found(1),
        );
        let burn_cap_router = borrow_global<Capability<BurnCapability<Coin>>>(account_addr);
        let mint_cap_router = borrow_global<Capability<MintCapability<Coin>>>(account_addr);
        
        Router::approve_coin<Coin>(account, mint_cap_router.cap, burn_cap_router.cap);
    }


    #[test_only]
    public entry fun initialize(account: &signer) {
        initialize_internal(account);
    }
    
    #[test_only]
    /// Extract mint or burn capability from user account.
    /// Returns extracted capability.
    public fun extract_capability<CapType: store>(account: &signer): CapType acquires Capability {
        let account_addr = signer::address_of(account);

        // Check if capability stored under account.
        assert!(exists<Capability<CapType>>(account_addr), ERR_CAP_MISSED);

        // Get capability stored under account.
        let Capability { cap } =  move_from<Capability<CapType>>(account_addr);
        cap
    }
    #[test_only]
    /// Put mint or burn `capability` under user account.
    public fun put_capability<CapType: store>(account: &signer, capability: CapType) {
        let account_addr = signer::address_of(account);

        // Check if capability doesn't exist under account so we can store.
        assert!(!exists<Capability<CapType>>(account_addr), ERR_CAP_EXISTS);

        // Store capability.
        move_to(account, Capability<CapType> {
            cap: capability
        });
    }


    #[test_only]
    use aptos_framework::account;

    #[test(from = @Multichain, to=@TEST)]
    fun test_coin(from: &signer, to: &signer) acquires Capability {
        initialize(from);

        let to_addr = signer::address_of(to);
        account::create_account_for_test(to_addr);

        coin::register<Coin>(to);

        assert!(coin::balance<Coin>(to_addr) == 0, 1);

        mint(from, to_addr, 100);

        std::debug::print(&coin::balance<Coin>(to_addr) );

        assert!(coin::balance<Coin>(to_addr) == 100, 2);

        copy_cap(from)

    }
}