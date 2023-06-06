// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IErrors {
    error ZERO();
    error NO_NFTS();
    error OWN_NFT();
    error BORROWED();
    error ONLY_ONE();
    error NOT_ZERO();
    error NOT_UINT8();
    error WRONG_FEE();
    error ZERO_PRICE();
    error NOT_LENDER();
    error NOT_UINT16();
    error CANT_RESET();
    error WRONG_TOKEN();
    error NOT_BORROWER();
    error MAX_DURATION();
    error ZERO_ADDRESS();
    error INVALID_SCALE();
    error INVALID_PRICE();
    error DIDNT_BORROWED();
    error INVALID_AMOUNT();
    error CRITICAL_ERROR();
    error TOKEN_SENTINEL();
    error R_ZERO_PAYMENT();
    error L_ZERO_PAYMENT();
    error NOT_ZERO_ADDRESS();
    error WAIT_RETURN_DATE();
    error PAST_RETURN_DATE();
    error INVALID_STANDARD();
}
