use starknet::ContractAddress;
use zklink_starknet_utils::math::fast_power10;

#[starknet::contract]
mod lending{
    //imports
    use super::ContractAddress;
    use super::fast_power10;
    
    //consts
    const LIQ_REWARD: u256 = 5;
    const LIQ_THRESHOLD: u256 = 80; //80%. Conv it to bps maybe
    const MIN_HEALTH_FACTOR: u256 = 1000000000000000000; //1e18

    //state vars
    #[storage]
    struct Storage {
        tokenToPriceFeed: LegacyMap<ContractAddress, ContractAddress>,
        accountToTokenDeposits: LegacyMap<(ContractAddress, ContractAddress), u256>,
        accountToTokenBorrows: LegacyMap<(ContractAddress, ContractAddress), u256>,
        allowedTokens: LegacyMap<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AllowedTokensSet: AllowedTokensSet,
        Deposit: Deposit,
        Borrow: Borrow,
        Withdraw: Withdraw,
        Repay: Repay,
        Liquidate: Liquidate,
    }

    #[derive(Drop, starknet::Event)]
    struct AllowedTokensSet {
        token: ContractAddress,
        priceFeed: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        account: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrow {
        account: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        account: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Repay {
        account: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Liquidate {
        account: ContractAddress,
        repayToken: ContractAddress,
        rewardToken: ContractAddress,
        halfDebtInEth: u256,
        liquidator: ContractAddress,
    }


    #[constructor]
    fn constructor(ref self: ContractState) {}


}



