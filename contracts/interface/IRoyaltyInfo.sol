// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

interface IRoyaltyInfo {
    function royaltyInfo(
        uint256 _tokenId, 
        uint256 price) 
        external 
        view 
        returns(uint96[] memory, address[] memory, uint256);
}