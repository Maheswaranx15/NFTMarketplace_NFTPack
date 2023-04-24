//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@openzeppelin/contracts/interfaces/IERC721.sol";

interface removePack {
    function removeFromPack(uint256[] memory _tokenIds) external;
}
