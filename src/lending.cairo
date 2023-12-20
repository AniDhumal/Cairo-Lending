use starknet::ContractAddress;
use zklink_starknet_utils::math::fast_power10;
use starknet::get_caller_address;
use starknet::get_contract_address;
use lending::utils::IERC20;
use lending::utils::IOracle;

#[starknet::contract]
mod lendingContract {
    //imports
    use core::traits::TryInto;
    use core::traits::Into;
    use super::ContractAddress;
    use super::fast_power10;
    use super::get_caller_address;
    use super::get_contract_address;
    use super::IERC20::IERC20Dispatcher;
    use super::IERC20::IERC20DispatcherTrait;
    use super::IOracle::IOracleDispatcher;
    use super::IOracle::IOracleDispatcherTrait;

    //consts
    const LIQ_REWARD: u256 = 5;
    const LIQ_THRESHOLD: u256 = 80; //80%. Conv it to bps maybe
    const TEN_POW_18: u256 = 1000000000000000000; //1e18

    //state vars
    #[storage]
    struct Storage {
        tokenToPriceFeed: LegacyMap<ContractAddress, ContractAddress>,
        accountToTokenDeposits: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        accountToTokenBorrows: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        allowedTokens: LegacyMap<ContractAddress, bool>,
        qUSD: ContractAddress, //deposit token
        wUSD: ContractAddress, //debt tokens
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
    impl LendingInternal of LendingInternalTrait {
        fn _check_allowed_tokens(ref self: ContractState, token: ContractAddress) {
            assert(self.allowedTokens.read(token) == true, 'Token not allowed');
        }

        fn _not_zero(ref self: ContractState, amount: u256) {
            assert(amount != 0, 'Amount zero');
        }

        fn _exchange_rate(ref self: ContractState, token: ContractAddress) -> u256 {
            return 1; //logic to be written
        }
        fn _check_utilization(ref self: ContractState, token: ContractAddress, amount: u256) {
            return; //logic to be written
        }
    }

    #[generate_trait]
    impl LendingExternal of LendingExternalTrait {
        fn deposit(ref self: ContractState, token: ContractAddress, amount: u256) {
            self._check_allowed_tokens(token);
            self._not_zero(amount);
            let caller = get_caller_address();
            let this = get_contract_address();
            self.accountToTokenDeposits.write((caller, token), amount);
            let success: bool = IERC20Dispatcher { contract_address: token }
                .transfer_from(caller, this, amount);
            assert(success == true, 'TransferFrom Failed');
            let token_oracle: ContractAddress = self.tokenToPriceFeed.read(token);
            let price_usd = IOracleDispatcher { contract_address: token_oracle }.getPrice(token);
            if (IERC20Dispatcher { contract_address: self.qUSD.read() }.total_supply() == 0) {
                let amount_qusd = amount * price_usd;
                IERC20Dispatcher { contract_address: self.qUSD.read() }.mint(caller, amount_qusd);
            } else {
                let amount_qusd = (amount * price_usd) / self._exchange_rate(token);
                IERC20Dispatcher { contract_address: self.qUSD.read() }.mint(caller, amount_qusd);
            }

            self.emit(Deposit { account: caller, token: token, amount: amount });
        }

        fn withdraw(ref self: ContractState, token: ContractAddress, amount_qusd: u256) {
            self._check_allowed_tokens(token);
            self._not_zero(amount_qusd);
            let caller = get_caller_address();
            let caller_balance = IERC20Dispatcher { contract_address: self.qUSD.read() }
                .balance_of(caller);
            assert(caller_balance >= amount_qusd, 'Insufficient balance');
            let this = get_contract_address();
            let token_oracle: ContractAddress = self.tokenToPriceFeed.read(token);
            let price_usd = IOracleDispatcher { contract_address: token_oracle }.getPrice(token);
            let mut amount_token = amount_qusd / price_usd;
            amount_token = amount_token * self._exchange_rate(token);
            self.accountToTokenDeposits.write((caller, token), caller_balance - amount_token);
            let success: bool = IERC20Dispatcher { contract_address: self.qUSD.read() }
                .burn(caller, amount_qusd);
            assert(success == true, 'qUSD transfer failed');
            let success2: bool = IERC20Dispatcher { contract_address: token }
                .transfer(caller, amount_token);
            assert(success2 == true, 'asset transfer failed');
            self.emit(Withdraw { account: caller, token: token, amount: amount_token });
        }

        fn borrow(
            ref self: ContractState,
            token_borrow: ContractAddress,
            amount_borrow: u256,
            token_collateral: ContractAddress,
            amount_collateral: u256,
        ) {
            self._check_allowed_tokens(token_borrow);
            self._check_allowed_tokens(token_collateral);
            self._not_zero(amount_borrow);
            self._check_utilization(token_borrow, amount_borrow);
            let caller = get_caller_address();
            let this = get_contract_address();
            let borrow_token_oracle = self.tokenToPriceFeed.read(token_borrow);
            let coll_token_oracle = self.tokenToPriceFeed.read(token_collateral);
            let borrow_token_price = IOracleDispatcher { contract_address: borrow_token_oracle }
                .getPrice(token_borrow);
            let coll_token_price = IOracleDispatcher { contract_address: coll_token_oracle }
                .getPrice(token_collateral);
            let borrow_value = (amount_borrow * borrow_token_price) / TEN_POW_18;
            let min_coll_value = (borrow_value * 8000) / 10000;
            let coll_value = (amount_collateral * coll_token_price) / TEN_POW_18;
            assert(coll_value <= min_coll_value, 'Collateral offered too low');
            self.accountToTokenBorrows.write((caller, token_borrow), self.accountToTokenBorrows.read((caller,token_borrow)) + amount_borrow);
            let success = IERC20Dispatcher { contract_address: token_collateral }
                .transfer_from(caller, this, amount_collateral);
            assert(success == true, 'Collateral transfer failed');
            let success2 = IERC20Dispatcher { contract_address: token_borrow }
                .transfer(caller, amount_borrow);
        }
    }
}

