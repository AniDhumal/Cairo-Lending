use starknet::ContractAddress;

#[starknet::interface]
trait IOracle<TContractState> {
    fn getPrice(self: @TContractState, token: ContractAddress) -> u256;
}
