// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "./utils/IERC20.sol";
import {IERC721} from "./utils/IERC721.sol";
import {ERC721Holder} from "lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC1155} from "lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC1155Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import {ILendData} from "./utils/ILendData.sol";
import {IErrors} from "./utils/IErrors.sol";
import {Ownable} from "./utils/Ownable.sol";


contract TXLend is ILendData, Ownable, ERC721Holder, ERC1155Receiver, ERC1155Holder {
    address payable private beneficiary;
    uint256 private constant SECONDS_IN_DAY = 86400;
    uint256 private lendingID = 1;
    uint256 private borrowingID = 1;
    uint256 public borrowFee = 100;

    mapping(uint8 => address) private tokenMap;
    mapping(bytes32 => Lending) private lendings;
    mapping(bytes32 => Borrowing) private borrowings;

    constructor(address payable beneficiary_) {
        isNotZero(beneficiary_);
        beneficiary = beneficiary_;
    }

    function lend(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendAmount,
        uint8[] memory maxBorrowDuration,
        bytes4[] memory dailyBorrowPrice,
        uint8[] memory paymentToken,
        bool[] memory willAutoRenew
    ) external {
        bundleCall(
            handleLend,
            createLendCallData(
                nftStandard,
                nftAddress,
                tokenID,
                lendAmount,
                maxBorrowDuration,
                dailyBorrowPrice,
                paymentToken,
                willAutoRenew
            )
        );
    }

    function stopLend(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID
    ) external {
        bundleCall(handleStopLend, createActionCallData(nftStandard, nftAddress, tokenID, _lendingID, new uint256[](0)));
    }

    function borrow(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID,
        uint8[] memory borrowDuration,
        uint256[] memory borrowAmount
    ) external payable {
        bundleCall(
            handleBorrow,
            createBorrowCallData(nftStandard, nftAddress, tokenID, _lendingID, borrowDuration, borrowAmount)
        );
    }

    function stopBorrow(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID,
        uint256[] memory _borrowingID
    ) external {
        bundleCall(handleStopBorrow, createActionCallData(nftStandard, nftAddress, tokenID, _lendingID, _borrowingID));
    }

    function claimBorrow(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID,
        uint256[] memory _borrowingID
    ) external {
        bundleCall(handleClaimBorrow, createActionCallData(nftStandard, nftAddress, tokenID, _lendingID, _borrowingID));
    }

    //
    //

    function handleLend(ILendData.CallData memory cd) internal {
        for (uint256 i = cd.left; i < cd.right;) {
            uint256 lendAmount = cd.lendAmount[i];
            if (lendAmount == 0) {
                revert IErrors.ZERO();
            }
            if (lendAmount > type(uint16).max) {
                revert IErrors.NOT_UINT16();
            }
            uint256 duration = cd.maxBorrowDuration[i];
            if (duration == 0) {
                revert IErrors.ZERO();
            }
            if (duration > type(uint8).max) {
                revert IErrors.NOT_UINT8();
            }
            if (uint32(cd.dailyBorrowPrice[i]) == 0) {
                revert IErrors.ZERO();
            }
            bytes32 identifier = keccak256(abi.encodePacked(cd.nftAddress[cd.left], cd.tokenID[i], lendingID));
            ILendData.Lending storage lending = lendings[identifier];
            isZero(lending.lenderAddress);
            if (lending.maxBorrowDuration != 0) {
                revert IErrors.NOT_ZERO();
            }
            if (lending.dailyBorrowPrice != 0) {
                revert IErrors.NOT_ZERO();
            }
            if (uint8(cd.paymentToken[i]) == 0) {
                revert IErrors.TOKEN_SENTINEL();
            }
            bool is721 = cd.nftStandard[i] == ILendData.NFTStandard.E721;
            uint16 _lendAmount = uint16(cd.lendAmount[i]);
            if (is721) {
                if (_lendAmount != 1) {
                    revert IErrors.ONLY_ONE();
                }
            }
            lendings[identifier] = ILendData.Lending({
                nftStandard: cd.nftStandard[i],
                lenderAddress: payable(msg.sender),
                maxBorrowDuration: cd.maxBorrowDuration[i],
                dailyBorrowPrice: cd.dailyBorrowPrice[i],
                lendAmount: _lendAmount,
                availableAmount: _lendAmount,
                paymentToken: cd.paymentToken[i],
                willAutoRenew: cd.willAutoRenew[i]
            });
            //emit ILendData.Lend(lendingID);
            ++lendingID;
            unchecked {
                ++i;
            }
        }
        safeTransfer(
            cd,
            msg.sender,
            address(this),
            sliceArr(cd.tokenID, cd.left, cd.right, 0),
            sliceArr(cd.lendAmount, cd.left, cd.right, 0)
        );
    }

    function handleStopLend(ILendData.CallData memory cd) internal {
        uint256 cR = cd.right;
        uint256 cL = cd.left;
        uint256[] memory lentAmounts = new uint256[](cR - cL);
        for (uint256 i = cL; i < cR;) {
            bytes32 lendingIdentifier = keccak256(abi.encodePacked(cd.nftAddress[cL], cd.tokenID[i], cd.lendingID[i]));
            Lending storage lending = lendings[lendingIdentifier];
            isNotZero(lending.lenderAddress);
            if (lending.maxBorrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (lending.dailyBorrowPrice == 0) {
                revert IErrors.ZERO();
            }
            if (lending.lenderAddress != msg.sender) {
                revert IErrors.NOT_LENDER();
            }
            if (cd.nftStandard[i] != lending.nftStandard) {
                revert IErrors.INVALID_STANDARD();
            }
            uint16 lAmount = lending.lendAmount;
            if (lAmount != lending.availableAmount) {
                revert IErrors.BORROWED();
            }
            lentAmounts[i - cL] = lAmount;
            //emit ILendData.StopLend(cd.lendingID[i]);
            delete lendings[lendingIdentifier];
            unchecked {
                ++i;
            }
        }
        safeTransfer(cd, address(this), msg.sender, sliceArr(cd.tokenID, cL, cR, 0), sliceArr(lentAmounts, cL, cR, cL));
    }

    function handleBorrow(ILendData.CallData memory cd) internal {
        uint256 cL = cd.left;
        for (uint256 i = cL; i < cd.right;) {
            uint256 id = cd.tokenID[i];
            bytes32 lendingIdentifier = keccak256(abi.encodePacked(cd.nftAddress[cL], id, cd.lendingID[i]));
            bytes32 borrowingIdentifier = keccak256(abi.encodePacked(cd.nftAddress[cL], id, borrowingID));
            ILendData.Lending storage lending = lendings[lendingIdentifier];
            ILendData.Borrowing storage borrowing = borrowings[borrowingIdentifier];
            isNotZero(lending.lenderAddress);
            if (lending.maxBorrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (lending.dailyBorrowPrice == 0) {
                revert IErrors.ZERO();
            }
            isZero(borrowing.borrowerAddress);
            if (borrowing.borrowDuration != 0) {
                revert IErrors.NOT_ZERO();
            }
            if (borrowing.borrowedAt != 0) {
                revert IErrors.NOT_ZERO();
            }
            if (msg.sender == lending.lenderAddress) {
                revert IErrors.OWN_NFT();
            }
            uint8 duration = cd.borrowDuration[i];
            if (duration > type(uint8).max) {
                revert IErrors.NOT_UINT8();
            }
            if (duration == 0) {
                revert IErrors.ZERO();
            }
            uint256 amount = cd.borrowAmount[i];
            if (amount > type(uint16).max) {
                revert IErrors.NOT_UINT16();
            }
            if (amount == 0) {
                revert IErrors.ZERO();
            }
            if (duration > lending.maxBorrowDuration) {
                revert IErrors.MAX_DURATION();
            }
            if (cd.nftStandard[i] != lending.nftStandard) {
                revert IErrors.INVALID_STANDARD();
            }
            if (amount > lending.availableAmount) {
                revert IErrors.INVALID_AMOUNT();
            }
            ERC20 paymentToken = ERC20(getPaymentToken(uint8(lending.paymentToken)));
            uint256 decimals = paymentToken.decimals();
            {
                uint256 borrowPrice = amount * duration * unpackPrice(lending.dailyBorrowPrice, 10 ** decimals);
                if (borrowPrice == 0) {
                    revert IErrors.ZERO_PRICE();
                }
                paymentToken.transferFrom(msg.sender, address(this), borrowPrice);
            }
            borrowings[borrowingIdentifier] = ILendData.Borrowing({
                borrowerAddress: payable(msg.sender),
                borrowAmount: uint16(amount),
                borrowDuration: duration,
                borrowedAt: uint32(block.timestamp)
            });
            lending.availableAmount -= uint16(amount);
            //emit ILendData.Borrow(borrowingID);
            ++borrowingID;
            unchecked {
                ++i;
            }
        }
    }

    function handleStopBorrow(ILendData.CallData memory cd) private {
        uint256 cL = cd.left;
        for (uint256 i = cL; i < cd.right;) {
            address nft = cd.nftAddress[cL];
            uint256 id = cd.tokenID[i];
            uint256 lId = cd.lendingID[i];
            uint256 bId = cd.borrowingID[i];
            bytes32 borrowingIdentifier = keccak256(abi.encodePacked(nft, id, bId));
            ILendData.Lending storage lending = lendings[keccak256(abi.encodePacked(nft, id, lId))];
            ILendData.Borrowing storage borrowing = borrowings[borrowingIdentifier];
            isNotZero(lending.lenderAddress);
            if (lending.maxBorrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (lending.dailyBorrowPrice == 0) {
                revert IErrors.ZERO();
            }
            isNotZero(borrowing.borrowerAddress);
            if (borrowing.borrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (borrowing.borrowedAt == 0) {
                revert IErrors.ZERO();
            }
            isReturnable(borrowing, msg.sender, block.timestamp);
            if (cd.nftStandard[i] != lending.nftStandard) {
                revert IErrors.INVALID_STANDARD();
            }
            if (borrowing.borrowAmount > lending.lendAmount) {
                revert IErrors.CRITICAL_ERROR();
            }
            uint256 secondsSinceBorrowStart = block.timestamp - borrowing.borrowedAt;
            distributePayments(lending, borrowing, secondsSinceBorrowStart);
            manageWillAutoRenew(lending, borrowing, nft, cd.nftStandard[cL], id, lId);
            //emit ILendData.StopBorrow(bId);
            delete borrowings[borrowingIdentifier];
            unchecked {
                ++i;
            }
        }
    }

    function handleClaimBorrow(CallData memory cd) private {
        uint256 cL = cd.left;
        for (uint256 i = cL; i < cd.right;) {
            address nft = cd.nftAddress[cL];
            uint256 id = cd.tokenID[i];
            uint256 lId = cd.lendingID[i];
            uint256 bId = cd.borrowingID[i];
            bytes32 borrowingIdentifier = keccak256(abi.encodePacked(nft, id, bId));
            ILendData.Lending storage lending = lendings[keccak256(abi.encodePacked(nft, id, lId))];
            ILendData.Borrowing storage borrowing = borrowings[borrowingIdentifier];
            isNotZero(lending.lenderAddress);
            if (lending.maxBorrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (lending.dailyBorrowPrice == 0) {
                revert IErrors.ZERO();
            }
            isNotZero(borrowing.borrowerAddress);
            if (borrowing.borrowDuration == 0) {
                revert IErrors.ZERO();
            }
            if (borrowing.borrowedAt == 0) {
                revert IErrors.ZERO();
            }
            if (isPastReturnDate(borrowing, block.timestamp) != true) {
                revert IErrors.WAIT_RETURN_DATE();
            }
            distributeClaimPayment(lending, borrowing);
            manageWillAutoRenew(lending, borrowing, nft, cd.nftStandard[cL], id, lId);
            //emit ILendData.BorrowClaimed(bId);
            delete borrowings[borrowingIdentifier];
            unchecked {
                ++i;
            }
        }
    }

    //
    //

    function manageWillAutoRenew(
        ILendData.Lending storage lending,
        ILendData.Borrowing storage borrowing,
        address nftAddress,
        ILendData.NFTStandard nftStandard,
        uint256 tokenID,
        uint256 lendingID
    ) internal {
        uint256 amount = lending.lendAmount;
        uint16 amountB = borrowing.borrowAmount;
        address lender = lending.lenderAddress;
        if (lending.willAutoRenew == false) {
            if (amount > amountB) {
                amount -= amountB;
                IERC1155(nftAddress).safeTransferFrom(address(this), lender, tokenID, uint256(amountB), "");
            } else if (amount == amountB) {
                if (nftStandard == ILendData.NFTStandard.E721) {
                    IERC721(nftAddress).transferFrom(address(this), lender, tokenID);
                } else {
                    IERC1155(nftAddress).safeTransferFrom(address(this), lender, tokenID, uint256(amountB), "");
                }
                delete lendings[keccak256(abi.encodePacked(nftAddress, tokenID, lendingID))];
            }
            //emit ILendData.StopLend(lendingID);
        } else {
            lending.availableAmount += amountB;
        }
    }

    function bundleCall(function(ILendData.CallData memory) handler, ILendData.CallData memory cd) internal {
        address[] memory nft = cd.nftAddress;
        uint256 cr = cd.right;
        uint256 cl = cd.left;
        if (nft.length == 0) {
            revert IErrors.NO_NFTS();
        }
        while (cr != nft.length) {
            if ((nft[cl] == nft[cr]) && (cd.nftStandard[cr] == ILendData.NFTStandard.E1155)) {
                ++cr;
            } else {
                handler(cd);
                cl = cr;
                ++cr;
            }
        }
        handler(cd);
    }

    function takeFee(uint256 borrowAmt, ERC20 token) internal returns (uint256 fee) {
        fee = borrowAmt * borrowFee / 10000;
        /* fee /= 10000; */
        token.transfer(beneficiary, fee);
    }

    function distributePayments(
        ILendData.Lending memory lending,
        ILendData.Borrowing memory borrowing,
        uint256 secondsSinceBorrowStart
    ) private {
        ERC20 paymentToken = ERC20(getPaymentToken(uint8(lending.paymentToken)));
        uint256 decimals = paymentToken.decimals();
        uint256 borrowPrice = borrowing.borrowAmount * unpackPrice(lending.dailyBorrowPrice, 10 ** decimals);
        uint256 totalBorrowerPmt = borrowPrice * borrowing.borrowDuration;
        if (totalBorrowerPmt == 0) {
            revert IErrors.R_ZERO_PAYMENT();
        }
        uint256 sendLenderAmt = (secondsSinceBorrowStart * borrowPrice) / SECONDS_IN_DAY;
        if (sendLenderAmt == 0) {
            revert IErrors.L_ZERO_PAYMENT();
        }
        if (borrowFee != 0) {
            uint256 takenFee = takeFee(sendLenderAmt, paymentToken);
            sendLenderAmt -= takenFee;
        }
        uint256 sendBorrowerAmt = totalBorrowerPmt - sendLenderAmt;
        paymentToken.transfer(lending.lenderAddress, sendLenderAmt);
        if (sendBorrowerAmt > 0) {
            paymentToken.transfer(borrowing.borrowerAddress, sendBorrowerAmt);
        }
    }

    function distributeClaimPayment(ILendData.Lending memory lending, ILendData.Borrowing memory borrowing) internal {
        uint8 paymentTokenIx = uint8(lending.paymentToken);
        ERC20 paymentToken = ERC20(getPaymentToken(paymentTokenIx));
        uint256 decimals = paymentToken.decimals();
        uint256 borrowPrice = borrowing.borrowAmount * unpackPrice(lending.dailyBorrowPrice, 10 ** decimals);
        uint256 finalAmt = borrowPrice * borrowing.borrowDuration;
        uint256 takenFee;
        if (borrowFee != 0) {
            takenFee = takeFee(finalAmt, paymentToken);
        }
        paymentToken.transfer(lending.lenderAddress, finalAmt - takenFee);
    }

    function safeTransfer(
        CallData memory cd,
        address from,
        address to,
        uint256[] memory tokenID,
        uint256[] memory lendAmount
    ) internal {
        uint256 cl = cd.left;
        if (cd.nftStandard[cl] == ILendData.NFTStandard.E721) {
            IERC721(cd.nftAddress[cl]).transferFrom(from, to, cd.tokenID[cl]);
        } else {
            IERC1155(cd.nftAddress[cl]).safeBatchTransferFrom(from, to, tokenID, lendAmount, "");
        }
    }

    //
    //

    function getLending9CFF8D4(address nftAddress, uint256 tokenID, uint256 _lendingID)
        external
        view
        returns (uint8, address, uint8, bytes4, uint16, uint16, uint8)
    {
        bytes32 identifier = keccak256(abi.encodePacked(nftAddress, tokenID, _lendingID));
        ILendData.Lending storage lending = lendings[identifier];
        return (
            uint8(lending.nftStandard),
            lending.lenderAddress,
            lending.maxBorrowDuration,
            lending.dailyBorrowPrice,
            lending.lendAmount,
            lending.availableAmount,
            uint8(lending.paymentToken)
        );
    }

    function getBorrowing144DC65D(address nftAddress, uint256 tokenID, uint256 _borrowingID)
        external
        view
        returns (address, uint16, uint8, uint32)
    {
        bytes32 identifier = keccak256(abi.encodePacked(nftAddress, tokenID, _borrowingID));
        ILendData.Borrowing storage borrowing = borrowings[identifier];
        return (borrowing.borrowerAddress, borrowing.borrowAmount, borrowing.borrowDuration, borrowing.borrowedAt);
    }

    //
    //

    function createLendCallData(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory lendAmount,
        uint8[] memory maxBorrowDuration,
        bytes4[] memory dailyBorrowPrice,
        uint8[] memory paymentToken,
        bool[] memory willAutoRenew
    ) internal pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nftStandard: nftStandard,
            nftAddress: nftAddress,
            tokenID: tokenID,
            lendAmount: lendAmount,
            lendingID: new uint256[](0),
            borrowingID: new uint256[](0),
            borrowDuration: new uint8[](0),
            borrowAmount: new uint256[](0),
            maxBorrowDuration: maxBorrowDuration,
            dailyBorrowPrice: dailyBorrowPrice,
            paymentToken: paymentToken,
            willAutoRenew: willAutoRenew
        });
    }

    function createBorrowCallData(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID,
        uint8[] memory borrowDuration,
        uint256[] memory borrowAmount
    ) internal pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nftStandard: nftStandard,
            nftAddress: nftAddress,
            tokenID: tokenID,
            lendAmount: new uint256[](0),
            lendingID: _lendingID,
            borrowingID: new uint256[](0),
            borrowDuration: borrowDuration,
            borrowAmount: borrowAmount,
            maxBorrowDuration: new uint8[](0),
            dailyBorrowPrice: new bytes4[](0),
            paymentToken: new uint8[](0),
            willAutoRenew: new bool[](0)
        });
    }

    function createActionCallData(
        ILendData.NFTStandard[] memory nftStandard,
        address[] memory nftAddress,
        uint256[] memory tokenID,
        uint256[] memory _lendingID,
        uint256[] memory _borrowingID
    ) internal pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nftStandard: nftStandard,
            nftAddress: nftAddress,
            tokenID: tokenID,
            lendAmount: new uint256[](0),
            lendingID: _lendingID,
            borrowingID: _borrowingID,
            borrowDuration: new uint8[](0),
            borrowAmount: new uint256[](0),
            maxBorrowDuration: new uint8[](0),
            dailyBorrowPrice: new bytes4[](0),
            paymentToken: new uint8[](0),
            willAutoRenew: new bool[](0)
        });
    }

    function unpackPrice(bytes4 price, uint256 scale) internal pure returns (uint256) {
        if (uint32(price) == 0) {
            revert IErrors.INVALID_PRICE();
        }
        if (scale < 10000) {
            revert IErrors.INVALID_SCALE();
        }
        uint16 whole = uint16(bytes2(price));
        uint16 decimal = uint16(bytes2(price << 16));
        uint256 decimalScale = scale / 10000;
        if (whole > 9999) {
            whole = 9999;
        }
        if (decimal > 9999) {
            decimal = 9999;
        }
        uint256 w = whole * scale;
        uint256 d = decimal * decimalScale;
        uint256 fullPrice = w + d;
        return (fullPrice);
    }

    function sliceArr(uint256[] memory arr, uint256 fromIx, uint256 toIx, uint256 arrOffset)
        internal
        pure
        returns (uint256[] memory r)
    {
        r = new uint256[](toIx - fromIx);
        for (uint256 i = fromIx; i < toIx;) {
            r[i - fromIx] = arr[i - arrOffset];
            unchecked {
                ++i;
            }
        }
    }

    //
    //
    function isNotZero(address addr) internal pure {
        assembly {
            if iszero(addr) { revert(0, 0) }
        }
    }

    function isZero(address addr) internal pure {
        assembly {
            if not(iszero(addr)) { revert(0, 0) }
        }
    }

    function isReturnable(Borrowing memory borrowing, address msgSender, uint256 blockTimestamp) internal pure {
        if (borrowing.borrowerAddress != msgSender) {
            revert IErrors.NOT_BORROWER();
        }
        if (isPastReturnDate(borrowing, blockTimestamp) != false) {
            revert IErrors.PAST_RETURN_DATE();
        }
    }

    function isPastReturnDate(Borrowing memory borrowing, uint256 nowTime) internal pure returns (bool) {
        uint256 at = borrowing.borrowedAt;
        if (nowTime <= at) {
            revert IErrors.DIDNT_BORROWED();
        }
        return (nowTime - at > borrowing.borrowDuration * SECONDS_IN_DAY);
    }

    function getPaymentToken(uint8 paymentToken) internal view returns (address) {
        return (tokenMap[paymentToken]);
    }

    //
    //

    function setPaymentToken(uint8 paymentToken, address t) external payable onlyOwner {
        if (paymentToken == 0) {
            revert IErrors.WRONG_TOKEN();
        }
        address token = tokenMap[paymentToken];
        if (token != address(0)) {
            revert IErrors.CANT_RESET();
        }
        token = t;
    }

    function setBorrowFee(uint256 borrowFee_) external payable onlyOwner {
        if (borrowFee_ >= 10000) {
            revert IErrors.WRONG_FEE();
        }
        assembly {
            sstore(borrowFee.slot, borrowFee_)
        }
    }

    function setBeneficiary(address payable beneficiary_) external payable onlyOwner {
        assembly {
            sstore(beneficiary.slot, beneficiary_)
        }
    }
}
