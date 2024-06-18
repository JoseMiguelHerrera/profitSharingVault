pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockAsset is ERC20 {
    constructor() ERC20("MockAsset", "MOCK") {}

    function mint(uint256 amount, address to) external {
        _mint(to, amount);
    }
}
