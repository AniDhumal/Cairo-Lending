use starknet::ContractAddress;
use zklink_starknet_utils::math::fast_power10;
use starknet::get_caller_address;
use starknet::get_contract_address;
use lending::utils::IERC20;

#[starknet::contract]
mod lendingContract{
    //imports
    use core::traits::TryInto;
use core::traits::Into;
use super::ContractAddress;
    use super::fast_power10;
    use super::get_caller_address;
    use super::get_contract_address;
    use super::IERC20::IERC20Dispatcher;
    use super::IERC20::IERC20DispatcherTrait;
    
    //consts
    const LIQ_REWARD: u256 = 5;
    const LIQ_THRESHOLD: u256 = 80; //80%. Conv it to bps maybe
    const MIN_HEALTH_FACTOR: u256 = 1000000000000000000; //1e18

    //state vars
    #[storage]
    struct Storage {
        tokenToPriceFeed: LegacyMap<ContractAddress, ContractAddress>,
        accountToTokenDeposits: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        accountToTokenBorrows: LegacyMap::<(ContractAddress, ContractAddress), u256>,
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

    #[generate_trait]
    impl LendingInternal of LendingInternalTrait{
        fn _check_allowed_tokens(ref self: ContractState, token: ContractAddress){
            assert(self.allowedTokens.read(token) == true, 'Token not allowed');
        }

        fn _not_zero(ref self:ContractState ,amount: u256){
            assert(amount != 0,'Amount zero');
        }
    }

    #[generate_trait]
    impl LendingExternal of LendingExternalTrait {
        fn deposit(ref self: ContractState, token: ContractAddress, amount: u256){
            self._check_allowed_tokens(token);
            self._not_zero(amount);
            let caller = get_caller_address();
            let this = get_contract_address();
            self.accountToTokenDeposits.write((caller, token), amount);
            let success: bool = IERC20Dispatcher{contract_address:token}.transfer_from(caller,this,amount);
            assert(success == true ,'TransferFrom Failed');
            self.emit(Deposit{account: caller, token: token, amount: amount});
        }
        
    }


}



