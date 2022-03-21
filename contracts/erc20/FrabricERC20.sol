// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./DividendERC20.sol";
import "../lists/FrabricWhitelist.sol";
import "./IntegratedLimitOrderDEX.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

// FrabricERC20s are tokens with a built in limit order DEX, along with governance and dividend functionality
// The owner can also mint tokens, with a whitelist enforced unless disabled by owner, defaulting to a parent whitelist
// Finally, the owner can pause transfers, intended for migrations and dissolutions
contract FrabricERC20 is OwnableUpgradeable, PausableUpgradeable, DividendERC20, FrabricWhitelist, IntegratedLimitOrderDEX, IFrabricERC20 {
  bool public mintable;

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool _mintable,
    address parentWhitelist,
    address dexToken
  ) external initializer {
    __DividendERC20_init(name, symbol);
    __Ownable_init();
    __Pausable_init();
    __FrabricWhitelist_init(parentWhitelist);
    __IntegratedLimitOrderDEX_init(dexToken);

    // Whitelist the initializer
    _setWhitelisted(msg.sender, keccak256("Initializer"));
    // Mint the supply
    _mint(msg.sender, supply);

    mintable = _mintable;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // Redefine ERC20 functions so the DEX can pick them up as overrides and call them
  function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, IntegratedLimitOrderDEX) {
    ERC20Upgradeable._transfer(from, to, amount);
  }
  function balanceOf(address account) public view override(ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint256) {
    return ERC20Upgradeable.balanceOf(account);
  }

  function mint(address to, uint256 amount) external override onlyOwner {
    require(mintable);
    _mint(to, amount);
  }

  // Whitelist functions
  function whitelisted(address person) public view override(IntegratedLimitOrderDEX, IWhitelist, FrabricWhitelist) returns (bool) {
    return FrabricWhitelist.whitelisted(person);
  }
  function setParentWhitelist(address whitelist) external override onlyOwner {
    _setParentWhitelist(whitelist);
  }
  function setWhitelisted(address person, bytes32 dataHash) external override onlyOwner {
    _setWhitelisted(person, dataHash);
  }
  function globallyAccept() external override onlyOwner {
    _globallyAccept();
  }

  // Pause functions
  function paused() public view override(PausableUpgradeable, IFrabricERC20) returns (bool) {
    return PausableUpgradeable.paused();
  }
  function pause() external override onlyOwner {
    _pause();
  }
  function unpause() external override onlyOwner {
    _unpause();
  }

  // Transfer requirements
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
    require(whitelisted(from) || (from == address(0)), "FrabricERC20: Token sender isn't whitelisted");
    require(whitelisted(to) || (to == address(0)), "FrabricERC20: Token recipient isn't whitelisted");
    require(!paused(), "FrabricERC20: Transfers are paused");
  }

  function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._afterTokenTransfer(from, to, amount);
    // Require the balance of the sender be greater than the amount of tokens they have on the DEX
    require(balanceOf(from) >= locked[from], "FrabricERC20: DEX orders exceed balance");
  }
}
