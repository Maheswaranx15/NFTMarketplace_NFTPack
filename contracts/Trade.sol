// SPDX-License-Identifier:UNLICENSED
pragma solidity 0.8.14;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interface/ITransferProxy.sol";
import "./interface/NFTpack.sol";
import "./interface/ILazymint.sol";
import "./interface/IRoyaltyInfo.sol";

contract Trade is AccessControl {
    enum BuyingAssetType {
        ERC1155,
        ERC721,
        LazyERC1155,
        LazyERC721
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event SellerFee(uint8 sellerFee);
    event BuyerFee(uint8 buyerFee);
    event BuyAsset(
        address indexed assetOwner,
        uint256[] indexed tokenId,
        uint256 quantity,
        address indexed buyer
    );
    event ExecuteBid(
        address indexed assetOwner,
        uint256[] indexed tokenId,
        uint256 quantity,
        address indexed buyer
    );

    // buyer platformFee
    uint8 private buyerFeePermille;

    //seller platformFee
    uint8 private sellerFeePermille;

    ITransferProxy public transferProxy;
    
    //contract owner
    address public owner;

    mapping(uint256 => bool) private usedNonce;

    // Create a new role identifier for the minter role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  /** Fee Struct
        @param platformFee  uint256 (buyerFee + sellerFee) value which is transferred to current contract owner.
        @param assetFee  uint256  assetvalue which is transferred to current seller of the NFT.
        @param royaltyFee  uint256 value, transferred to Minter of the NFT.
        @param price  uint256 value, the combination of buyerFee and assetValue.
        @param tokenCreator address value, it's store the creator of NFT.
     */
    struct Fee {
        uint256 platformFee;
        uint256 assetFee;
        uint96[] royaltyFee;
        uint256 price;
        address[] tokenCreator;
    }

    /* An ECDSA signature. */
    struct Sign {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
    }
   

    struct Order {
        address seller;
        address buyer;
        address erc20Address;
        address nftAddress;
        BuyingAssetType nftType;
        uint256 unitPrice;
        bool skipRoyalty;
        uint256 amount;
        string tokenURI;
        uint256 supply;
        uint96[] royaltyFee;
        address[] receivers;
        uint256 qty;
        uint256[] tokenId;
        bool isPacked;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor(
        uint8 _buyerFee,
        uint8 _sellerFee,
        ITransferProxy _transferProxy
    ) {
        buyerFeePermille = _buyerFee;
        sellerFeePermille = _sellerFee;
        transferProxy = _transferProxy;
        owner = msg.sender;
        _setupRole("ADMIN_ROLE", msg.sender);
    }

    /**
        returns the buyerservice Fee in multiply of 1000.
     */

    function buyerServiceFee() external view virtual returns (uint8) {
        return buyerFeePermille;
    }

    /**
        returns the sellerservice Fee in multiply of 1000.
     */

    function sellerServiceFee() external view virtual returns (uint8) {
        return sellerFeePermille;
    }

    /** 
        @param _buyerFee  value for buyerservice in multiply of 1000.
    */

    function setBuyerServiceFee(uint8 _buyerFee)
        external
        onlyRole("ADMIN_ROLE")
        returns (bool)
    {
        buyerFeePermille = _buyerFee;
        emit BuyerFee(buyerFeePermille);
        return true;
    }

    /** 
        @param _sellerFee  value for buyerservice in multiply of 1000.
    */

    function setSellerServiceFee(uint8 _sellerFee)
        external
        onlyRole("ADMIN_ROLE")
        returns (bool)
    {
        sellerFeePermille = _sellerFee;
        emit SellerFee(sellerFeePermille);
        return true;
    }

    /**
        transfers the contract ownership to newowner address.    
        @param newOwner address of newOwner
     */

    function transferOwnership(address newOwner)
        external
        onlyRole("ADMIN_ROLE")
        returns (bool)
    {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _revokeRole("ADMIN_ROLE", owner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        _setupRole("ADMIN_ROLE", newOwner);
        return true;
    }

    function removeFromPack(address nftAddress, uint256[] calldata tokenIds) external onlyOwner {
            removePack(nftAddress).removeFromPack(tokenIds);
    }


    /**
        excuting the NFT order.
        @param order ordervalues(seller, buyer,...).
        @param sign Sign value(v, r, f).
    */

    function buyAsset(Order calldata order, Sign calldata sign)
        external
        returns (bool)
    {
        require(!usedNonce[sign.nonce], "Nonce : Invalid Nonce");
        usedNonce[sign.nonce] = true;
        if(order.isPacked) {
            removePack(order.nftAddress).removeFromPack(order.tokenId);
        }
        Fee memory fee = getFees(
            order
        );
        bytes memory tokenIdHash = _encode(order.tokenId);
        require(
            (fee.price >= order.unitPrice * order.qty),
            "Paid invalid amount"
        );
        verifySellerSign(
            order.seller,
            order.unitPrice,
            order.erc20Address,
            order.nftAddress,
            tokenIdHash,
            sign
        );
        address buyer = msg.sender;
        tradeAsset(order, fee, buyer, order.seller);
        emit BuyAsset(order.seller, order.tokenId, order.qty, msg.sender);
        return true;
    }

    /**
        excuting the NFT order.
        @param order ordervalues(seller, buyer,...).
        @param sign Sign value(v, r, f).
    */

    function executeBid(Order calldata order, Sign calldata sign)
        external
        returns (bool)
    {
        require(!usedNonce[sign.nonce], "Nonce : Invalid Nonce");
        usedNonce[sign.nonce] = true;
        if(order.isPacked) {
            removePack(order.nftAddress).removeFromPack(order.tokenId);
        }
        Fee memory fee = getFees(
            order
        );
        bytes memory tokenIdHash = _encode(order.tokenId);
        verifyBuyerSign(
            order.buyer,
            order.amount,
            order.erc20Address,
            order.nftAddress,
            order.qty,
            tokenIdHash,
            sign
        );
        address seller = msg.sender;
        tradeAsset(order, fee, order.buyer, seller);
        emit ExecuteBid(msg.sender, order.tokenId, order.qty, order.buyer);
        return true;
    }


    function mintAndBuyAsset(Order calldata order, Sign calldata sign, Sign calldata ownerSign)
        external
        returns (bool)
    {
        require(!usedNonce[sign.nonce], "Nonce : Invalid Nonce");
        usedNonce[sign.nonce] = true;
        if(order.isPacked) {
            removePack(order.nftAddress).removeFromPack(order.tokenId);
        }
        Fee memory fee = getFees(
            order
        );
        bytes memory tokenIdHash = _encode(order.tokenId);
        require(
            (fee.price >= order.unitPrice * order.qty),
            "Paid invalid amount"
        );
        verifyOwnerSign(
            order.seller,
            order.tokenURI,
            order.nftAddress,
            ownerSign
        );
        verifySellerSign(
            order.seller,
            order.unitPrice,
            order.erc20Address,
            order.nftAddress,
            tokenIdHash,
            sign
        );
        address buyer = msg.sender;
        tradeAsset(order, fee, buyer, order.seller);
        emit BuyAsset(order.seller, order.tokenId, order.qty, msg.sender);
        return true;
    }
    function mintAndExecuteBid(Order calldata order, Sign calldata sign, Sign calldata ownerSign)
        external
        returns (bool)
    {
        require(!usedNonce[sign.nonce], "Nonce : Invalid Nonce");
        usedNonce[sign.nonce] = true;
        if(order.isPacked) {
            removePack(order.nftAddress).removeFromPack(order.tokenId);
        }
        Fee memory fee = getFees(
            order
        );
        verifyOwnerSign(
            order.seller,
            order.tokenURI,
            order.nftAddress,
            ownerSign
        );
        bytes memory tokenIdHash = _encode(order.tokenId);
        verifyBuyerSign(
            order.buyer,
            order.amount,
            order.erc20Address,
            order.nftAddress,
            order.qty,
            tokenIdHash,
            sign
        );
        address seller = msg.sender;
        tradeAsset(order, fee, order.buyer, seller);
        emit ExecuteBid(msg.sender, order.tokenId, order.qty, order.buyer);
        return true;
    }

    /**
        returns the signer of given signature.
     */
    function getSigner(bytes32 hash, Sign memory sign)
        internal
        pure
        returns (address)
    {
        return
            ecrecover(
                keccak256(
                    abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
                ),
                sign.v,
                sign.r,
                sign.s
            );
    }

    function verifySellerSign(
        address seller,
        uint256 amount,
        address paymentAssetAddress,
        address assetAddress,
        bytes memory tokenIdHash,
        Sign memory sign
    ) internal pure {
        bytes32 hash = keccak256(
            abi.encodePacked(
                assetAddress, 
                paymentAssetAddress,
                tokenIdHash,
                amount,
                sign.nonce
            )
        );
        require(
            seller == getSigner(hash, sign),
            "seller sign verification failed"
        );
    }

    function verifyBuyerSign(
        address buyer,
        uint256 amount,
        address paymentAssetAddress,
        address assetAddress,
        uint256 qty,
        bytes memory tokenIdHash,
        Sign memory sign
    ) internal pure {
        bytes32 hash = keccak256(
            abi.encodePacked(
                assetAddress,
                paymentAssetAddress,
                tokenIdHash,
                amount,
                qty,
                sign.nonce
            )
        );
        require(
            buyer == getSigner(hash, sign),
            "buyer sign verification failed"
        );
    }

        function verifyOwnerSign(
        address seller,
        string memory tokenURI,
        address assetAddress,
        Sign memory sign
    ) internal view {
        bytes32 hash = keccak256(
            abi.encodePacked(
                this,
                assetAddress,
                seller,
                tokenURI,
                sign.nonce
            )
        );
        require(
            owner == getSigner(hash, sign),
            "owner sign verification failed"
        );
    }

    /**
        it retuns platformFee, assetFee, royaltyFee, price and tokencreator.
     */
    function getFees(Order calldata order) internal view returns(Fee memory) {
        uint platformFee;
        uint royalty;
        uint96[] memory _royaltyFee;
        address[] memory _tokenCreator;
        uint assetFee;
        uint price = order.amount * 1000 / (1000 + buyerFeePermille);
        uint buyerFee = order.amount - price;
        uint sellerFee = price * sellerFeePermille / 1000;
        platformFee = buyerFee + sellerFee;
        if (order.nftType == BuyingAssetType.ERC721 && order.isPacked) {
            for( uint256 i = 0; i < (order.tokenId).length; i++) {
                (_royaltyFee, _tokenCreator, royalty) = IRoyaltyInfo(order.nftAddress)
                .royaltyInfo(order.tokenId[i], price);      
            }
        }
        if(!order.skipRoyalty &&((order.nftType == BuyingAssetType.ERC721) || (order.nftType == BuyingAssetType.ERC1155)) && !order.isPacked) {
            (_royaltyFee, _tokenCreator, royalty) = IRoyaltyInfo(order.nftAddress)
                    .royaltyInfo(order.tokenId[0], price);        
        }
        if(!order.skipRoyalty &&((order.nftType == BuyingAssetType.LazyERC721) || (order.nftType == BuyingAssetType.LazyERC1155))) {
                _royaltyFee = new uint96[](order.royaltyFee.length);
                _tokenCreator = new address[](order.receivers.length);
                for( uint256 i =0; i< order.receivers.length; i++) {
                    royalty += uint96(price * order.royaltyFee[i] / 1000) ;
                    (_tokenCreator[i], _royaltyFee[i]) = (order.receivers[i], uint96(price * order.royaltyFee[i] / 1000));
                }     
        }
        assetFee = price - royalty - sellerFee;
        return Fee(platformFee, assetFee, _royaltyFee, price, _tokenCreator);
    }

    /** 
        transfers the NFTs and tokens...
        @param order ordervalues(seller, buyer,...).
        @param fee Feevalues(platformFee, assetFee,...).
    */

    function tradeAsset(
        Order calldata order,
        Fee memory fee,
        address buyer,
        address seller
    ) internal virtual {
        if (order.nftType == BuyingAssetType.ERC721) {
            for( uint256 i = 0; i < order.tokenId.length; i++) {
                transferProxy.erc721safeTransferFrom(
                IERC721(order.nftAddress), 
                seller, 
                buyer, 
                order.tokenId[i]);
            }
        }
        if (order.nftType == BuyingAssetType.ERC1155) {
            transferProxy.erc1155safeTransferFrom(
                IERC1155(order.nftAddress),
                seller,
                buyer,
                order.tokenId[0],
                order.qty,
                ""
            );
        }
        if (order.nftType == BuyingAssetType.LazyERC721) {
            ILazyMint(order.nftAddress).mintAndTransfer(
                seller,
                buyer,
                order.tokenURI,
                order.royaltyFee,
                order.receivers
            );
        }
        if (order.nftType == BuyingAssetType.LazyERC1155) {
            ILazyMint(order.nftAddress).mintAndTransfer(
                seller,
                buyer,
                order.tokenURI,
                order.royaltyFee,
                order.receivers,
                order.supply,
                order.qty
            );
        }
        if (fee.platformFee > 0) {
            transferProxy.erc20safeTransferFrom(
                IERC20(order.erc20Address),
                buyer,
                owner,
                fee.platformFee
            );
        }
        for(uint96 i = 0; i < fee.tokenCreator.length; i++) {
            if (fee.royaltyFee[i] > 0 && (!order.skipRoyalty)) {
                transferProxy.erc20safeTransferFrom(
                    IERC20(order.erc20Address),
                    buyer,
                    fee.tokenCreator[i],
                    fee.royaltyFee[i]
                );
            }
        }
        transferProxy.erc20safeTransferFrom(
            IERC20(order.erc20Address),
            buyer,
            seller,
            fee.assetFee
        );
    }

    function _encode(uint256[] memory data) internal pure returns(bytes memory) {
        return  abi.encode(data);
    }
}
