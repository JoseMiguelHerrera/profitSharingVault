// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/ProfitSharingVault.sol";
import "../src/MockAsset.sol";

contract ProfitSharingVaultTest is Test {

    MockAsset public asset;
    ProfitSharingVault public vault;
    address public strategy= address(123456);

    address public addressDistributor= address(999);
    address public withdrawAdmin = address(555);

    address public user1 = address(1);
    address public user2 = address(2);

    function setUp() public {
        asset = new MockAsset();
        vault = new ProfitSharingVault(address(asset),strategy,"strategyURI","testStrategy",true,addressDistributor,withdrawAdmin);
    }

    function testHere() public {
        //add tests
    }

}