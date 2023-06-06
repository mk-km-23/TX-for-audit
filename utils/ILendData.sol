// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILendData {
    event Lend(
        bool is721,
        address indexed lenderAddress,
        address indexed nftAddress,
        uint256 indexed tokenID,
        uint256 lendingID,
        uint8 maxBorrowDuration,
        bytes4 dailyBorrowPrice,
        uint16 lendAmount,
        uint8 paymentToken,
        bool willAutoRenew
    );

    event Borrow(
        address indexed borrowerAddress,
        uint256 lendingID,
        uint256 borrowingID,
        uint16 borrowAmount,
        uint8 borrowDuration,
        uint32 borrowedAt
    );

    event StopLend(uint256 indexed lendingID, uint32 stoppedAt, uint16 amount);

    event StopBorrow(uint256 indexed borrowingID, uint32 stoppedAt);

    event BorrowClaimed(uint256 indexed borrowingID, uint32 collectedAt);

    enum NFTStandard {
        E721,
        E1155
    }

    struct CallData {
        uint256 left;
        uint256 right;
        NFTStandard[] nftStandard;
        address[] nftAddress;
        uint256[] tokenID;
        uint256[] lendAmount;
        uint8[] maxBorrowDuration;
        bytes4[] dailyBorrowPrice;
        uint256[] lendingID;
        uint256[] borrowingID;
        uint8[] borrowDuration;
        uint256[] borrowAmount;
        uint8[] paymentToken;
        bool[] willAutoRenew;
    }

    struct Lending {
        NFTStandard nftStandard;
        address payable lenderAddress;
        uint8 maxBorrowDuration;
        bytes4 dailyBorrowPrice;
        uint16 lendAmount;
        uint16 availableAmount;
        uint8 paymentToken;
        bool willAutoRenew;
    }

    struct Borrowing {
        address payable borrowerAddress;
        uint8 borrowDuration;
        uint32 borrowedAt;
        uint16 borrowAmount;
    }

    function lend(
        NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendAmount,
        uint8[] memory maxBorrowDuration,
        bytes4[] memory dailyBorrowPrice,
        uint8[] memory paymentToken,
        bool[] memory willAutoRenew
    ) external;

    function stopLend(
        NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendingID
    ) external;

    function borrow(
        NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendingID,
        uint8[] memory borrowDuration,
        uint256[] memory borrowAmount
    ) external payable;

    function stopBorrow(
        NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendingID,
        uint256[] memory borrowingID
    ) external;

    function claimBorrow(
        NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendingID,
        uint256[] memory borrowingID
    ) external;
}
