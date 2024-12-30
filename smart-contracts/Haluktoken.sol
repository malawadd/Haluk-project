// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HalukToken is ERC20, Ownable {
    // The total supply is set to 100,000,000 HALUK (with 18 decimals).
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10**18;

    /**
     * @dev Mints the initial supply to the contract deployer.
     *      Token name:     "Haluk Token"
     *      Token symbol:   "HALUK"
     *      Decimals:       18
     */
    constructor(address initialOwner) ERC20("Haluk Token", "HALUK") Ownable(initialOwner) {
        // Mint the entire initial supply to the deployer (the contract owner).
        _mint(initialOwner, INITIAL_SUPPLY);
    }

  
}
