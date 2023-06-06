// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SwapData} from "./SwapData.sol";
import {Ownable} from "./utils/Ownable.sol";
import {IERC721} from "./utils/IERC721.sol";
import {HandleERC20} from "./utils/HandleERC20.sol";
import {HandleERC721} from "./utils/HandleERC721.sol";
import {ERC721Holder} from "./utils/ERC721Holder.sol";


contract TXswap is SwapData, Ownable, HandleERC20, HandleERC721, ERC721Holder {
    /////////////////////////////////////////////
    //                 Errors
    /////////////////////////////////////////////

    error Unauthorized();
    error NotActive();
    error NotEnoughEth();

    /////////////////////////////////////////////
    //                 Events
    /////////////////////////////////////////////

    event PutSwap(uint256 indexed id);
    event CancelSwap(uint256 indexed id);
    event AcceptSwap(uint256 indexed id);

    /////////////////////////////////////////////
    //                 Storage
    /////////////////////////////////////////////

    Swap[] public swaps;

    address public protocol;
    address public xNft;
    uint256 public flatFee;
    uint256 public discountedFee;
    uint256 public fee;
    bool public mutex;

    /////////////////////////////////////////////
    //                  Swap
    /////////////////////////////////////////////

    /**
     * @dev Creates a new swap by the seller with the specified NFTs and tokens offered.
     * @param nftsGiven Array of addresses of the NFTs given by the seller.
     * @param idsGiven Array of IDs of the NFTs given by the seller.
     * @param nftsWanted Array of addresses of the NFTs wanted by the seller.
     * @param buyer The address of the buyer for the swap.
     * @param tokenWanted The address of the ERC20 token wanted by the seller.
     * @param amount The amount of ERC20 tokens wanted by the seller.
     * @param ethAmount The amount of ether wanted by the seller.
     * Emits a {PutSwap} event indicating the creation of the swap and its ID.
     */
    function putSwap(
        address[] memory nftsGiven,
        uint256[] memory idsGiven,
        address[] memory nftsWanted,
        address buyer,
        address tokenWanted,
        uint256 amount,
        uint256 ethAmount
    ) external noReentrancy {
        transferNft(nftsGiven, msg.sender, address(this), nftsGiven.length, idsGiven);

        swaps.push(
            Swap({
                active: true,
                seller: msg.sender,
                buyer: buyer,
                giveNft: nftsGiven,
                giveId: idsGiven,
                wantNft: nftsWanted,
                wantToken: tokenWanted,
                amount: amount,
                ethAmount: ethAmount
            })
        );

        uint256 id = swaps.length - 1;

        emit PutSwap(id);
    }

    /**
     * @dev Allows the seller to cancel an active swap and transfer the ERC721 tokens back to the seller.
     * @param id The ID of the swap to be cancelled.
     */
    function cancelSwap(uint256 id) external noReentrancy {
        Swap storage swap = swaps[id];
        address sseller = swap.seller;

        if (msg.sender != sseller) {
            revert Unauthorized();
        }
        if (swap.active == false) {
            revert NotActive();
        }

        swap.active = false;

        transferNft(swap.giveNft, address(this), sseller, swap.giveNft.length, swap.giveId);

        emit CancelSwap(id);
    }

    /**
     * @dev Allows the buyer to accept a swap by ID and transfer the assets to the respective parties.
     * @param id The ID of the swap to be accepted.
     * @param tokenIds An array of token IDs for ERC721 tokens.
     */
    function acceptSwap(uint256 id, uint256[] memory tokenIds) public payable noReentrancy {
        Swap storage swap = swaps[id];

        if (swap.active == false) {
            revert NotActive();
        }

        if (swap.buyer != address(0)) {
            if (msg.sender != swap.buyer) {
                revert Unauthorized();
            }
        }

        swap.active = false;

        // variable fee
        uint256 fee_;
        if (IERC721(xNft).balanceOf(msg.sender) != 0) {
            fee_ = discountedFee;
        } else {
            fee_ = fee;
        }

        address[] memory swantNft = swap.wantNft;
        address[] memory sgiveNft = swap.giveNft;
        uint256[] memory sgiveId = swap.giveId;
        address sseller = swap.seller;
        address swantToken = swap.wantToken;
        uint256 lenWantNft = swantNft.length;
        uint256 sethAmount = swap.ethAmount;
        uint256 samount = swap.amount;

        if (lenWantNft != 0) {
            transferNft(swantNft, msg.sender, sseller, lenWantNft, tokenIds);
        }

        if (swantToken != address(0)) {
            uint256 protocolTokenFee = samount / fee_;
            uint256 finalTokenAmount = samount - protocolTokenFee;

            transferToken(swantToken, msg.sender, sseller, protocol, finalTokenAmount, protocolTokenFee);
        }

        if (sethAmount != 0) {
            if (msg.value < sethAmount) {
                revert NotEnoughEth();
            }
            uint256 protocolEthFee = msg.value / fee_;
            uint256 finalEthAmount = sethAmount - protocolEthFee;

            (bool sent1,) = address(sseller).call{value: finalEthAmount}("");
            require(sent1, "!Call");

            (bool sent2,) = protocol.call{value: protocolEthFee}("");
            require(sent2, "!Call");
        }

        if (lenWantNft != 0 && swantToken == address(0) && sethAmount == 0) {
            if (msg.value < flatFee) {
                revert NotEnoughEth();
            }

            (bool sent,) = protocol.call{value: flatFee}("");
            require(sent, "!Call");
        }

        transferNft(sgiveNft, address(this), msg.sender, sgiveNft.length, sgiveId);

        emit AcceptSwap(id);
    }

    /////////////////////////////////////////////
    //                  Admin
    /////////////////////////////////////////////

    /**
     * @dev Function to set the protocol address.
     * @param protocol_ The address of the protocol.
     */
    function setProtocol(address protocol_) external onlyOwner {
        assembly {
            sstore(protocol.slot, protocol_)
        }
    }

    /**
     * @dev Allows the contract owner to set the transaction fee.
     * @param fee_ The new transaction fee.
     */
    function setFee(uint256 fee_) external onlyOwner {
        assembly {
            sstore(fee.slot, fee_)
        }
    }

    /**
     * @dev Allows the contract owner to set the discounted transaction fee.
     * @param discountedFee_ The new discounted transaction fee.
     */
    function setDiscountedFee(uint256 discountedFee_) external onlyOwner {
        assembly {
            sstore(discountedFee.slot, discountedFee_)
        }
    }

    /**
     * @dev Allows the contract owner to set the flat transaction fee.
     * @param flatFee_ The new flat transaction fee.
     */
    function setFlatFee(uint256 flatFee_) external onlyOwner {
        assembly {
            sstore(flatFee.slot, flatFee_)
        }
    }

    /**
     * @dev Allows the contract owner to set the txswap's nft contract address.
     * @param xNft_ txswap's nft contract address.
     */
    function setXNft(address xNft_) external onlyOwner {
        assembly {
            sstore(xNft.slot, xNft_)
        }
    }

    /////////////////////////////////////////////
    //                Modifiers
    /////////////////////////////////////////////

    modifier noReentrancy() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        require(!mutex, "lol!");
        mutex = true;
    }

    function _nonReentrantAfter() internal {
        mutex = false;
    }

    /////////////////////////////////////////////
    //                Getter
    /////////////////////////////////////////////

    /**
     * @dev Returns the number of swaps in the contract.
     * @return The length of the swaps array.
     */
    function getLength() external view returns (uint256) {
        return swaps.length;
    }

    /**
     * @dev Returns the details of a specific swap by its ID.
     * @param id The ID of the swap to be retrieved.
     * @return The details of the swap as a memory struct.
     */
    function getSwap(uint256 id) external view returns (Swap memory) {
        return swaps[id];
    }
}
