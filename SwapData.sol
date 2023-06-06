// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

contract SwapData {
    struct Swap {
        uint256[] giveId;
        uint256 amount;
        uint256 ethAmount;
        address seller;
        address buyer;
        address[] giveNft;
        address[] wantNft;
        address wantToken;
        bool active;
    }
}
