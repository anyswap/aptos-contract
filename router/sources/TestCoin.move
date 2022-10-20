#[test_only]
module Bob::TestCoin {
    use std::string;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use std::signer;
    use std::error;
    
    // Errors.

    /// When capability is missed on account.
    const ERR_CAP_MISSED: u64 = 100;

    /// When capability already exists on account.
    const ERR_CAP_EXISTS: u64 = 101;

    /// Represents new user coin.
    /// Indeeed this type will be used as CoinType for your new coin.
    struct MyCoin has key {}

    /// The struct to store capability: mint and burn.
    struct Capability<CapType: store> has key {
        cap: CapType
    }

    /// Initializing `MyCoin` as coin in Aptos network.
    public fun initialize_internal(account: &signer) {
        // Initialize `MyCoin` as coin type using Aptos Framework.
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyCoin>(
            account,
            string::utf8(b"MyCoin"),
            string::utf8(b"MC"),
            10,
            true,
        );

        // Store mint and burn capabilities under user account.
        move_to(account, Capability { cap: mint_cap });
        move_to(account, Capability { cap: burn_cap });
        move_to(account, Capability { cap: freeze_cap });
    }

    /// Similar to `initialize_internal` but can be executed as script.
    public entry fun initialize(account: &signer) {
        initialize_internal(account);
    }

    // mint
    public entry fun mint(
        account: &signer,
        dst_addr: address,
        amount: u64,
    ) acquires Capability {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Capability<MintCapability<MyCoin>>>(account_addr),
            error::not_found(0),
        );
        let capabilities = borrow_global<Capability<MintCapability<MyCoin>>>(account_addr);
        let coins_minted = coin::mint(amount, &capabilities.cap);
        coin::deposit(dst_addr, coins_minted);
    }

     public entry fun burn(
        account: &signer,
        amount: u64,
    ) acquires Capability {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Capability<BurnCapability<MyCoin>>>(account_addr),
            error::not_found(0),
        );
        let capabilities = borrow_global<Capability<BurnCapability<MyCoin>>>(account_addr);
        let to_burn = coin::withdraw<MyCoin>(account, amount);
        coin::burn(to_burn, &capabilities.cap);
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

    #[test(from = @Bob, to=@0x1)]
    fun test_coin(from: &signer, to: &signer) acquires Capability {
        initialize(from);

        let to_addr = signer::address_of(to);
        account::create_account_for_test(to_addr);

        coin::register<MyCoin>(to);

        assert!(coin::balance<MyCoin>(to_addr) == 0, 1);

        // let mint_cap = extract_capability(from);
        // let coins_minted = coin::mint<MyCoin>(100, &mint_cap);
        // coin::deposit(to_addr, coins_minted);
        // put_capability(from,mint_cap );

        mint(from, to_addr, 100);

        std::debug::print(&coin::balance<MyCoin>(to_addr) );

        assert!(coin::balance<MyCoin>(to_addr) == 100, 2);

    }
}