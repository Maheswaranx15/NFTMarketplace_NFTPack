// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract NFT721 is
    Context,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721URIStorage,
    AccessControl
{

    using Counters for Counters.Counter;


    Counters.Counter private _tokenIdTracker;


    string private baseTokenURI;


    address public owner;


    mapping(uint256 => bool) private usedNonce;


    address public operator;



    mapping(uint256 => TokenRoyalty) private tokenRoyalty;

    mapping(uint256 => bool) private isPacked;

    

    

    struct Sign {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
    }



    struct TokenRoyalty {
        uint96[] royaltyPermiles;
        address[] receivers;
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event Pack(uint256[] tokenIds);
    event RemovedFromPack(uint256[] tokenIds);

    constructor(
        string memory name,
        string memory symbol,
        string memory _baseTokenURI,
        address _operator
    ) ERC721(name, symbol) {
        baseTokenURI = _baseTokenURI;
        owner = _msgSender();
        operator = _operator;
        _setupRole("ADMIN_ROLE", msg.sender);
        _setupRole("OPERATOR_ROLE", operator);
        _tokenIdTracker.increment();
    }

  
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
        owner = newOwner;
        _setupRole("ADMIN_ROLE", newOwner);
        emit OwnershipTransferred(owner, newOwner);
        return true;
    }



    function baseURI() external view returns (string memory) {
        return _baseURI();
    }

   

    function setBaseURI(string memory _baseTokenURI) external onlyRole("ADMIN_ROLE") {
        baseTokenURI = _baseTokenURI;
    }

    function mint(
        string memory _tokenURI,
        uint96[] calldata _royaltyFee,
        address[] calldata _receivers,
        Sign calldata sign
    ) external virtual returns (uint256 _tokenId) {

        require(!usedNonce[sign.nonce], "Nonce : Invalid Nonce");
        usedNonce[sign.nonce] = true;
        verifySign(_tokenURI, msg.sender, sign);
        _tokenId = _tokenIdTracker.current();
        _mint(_msgSender(), _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        _setTokenRoyalty(_tokenId, _royaltyFee, _receivers);
        _tokenIdTracker.increment();
        return _tokenId;
    }


    
    function mintAndTransfer(
        address from,
        address to,
        string memory _tokenURI,
        uint96[] calldata _royaltyFee,
        address[] calldata _receivers
    ) external virtual onlyRole("OPERATOR_ROLE") returns(uint256 _tokenId) {
        if(!isApprovedForAll(from, operator)) {
            _setApprovalForAll(from, operator, true);
        }
        _tokenId = _tokenIdTracker.current();
        _mint(from, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        _setTokenRoyalty(_tokenId, _royaltyFee, _receivers);
        safeTransferFrom(from, to, _tokenId, "");
        _tokenIdTracker.increment();
        return _tokenId;  
    }

    function createNFTPack(uint256 NFTsToBeCreate, string[] calldata _tokenURIs, address[] calldata _royaltyReceivers, uint96[] calldata _royaltyFees) external onlyRole("ADMIN_ROLE") virtual returns(bool) {
        require( NFTsToBeCreate == _tokenURIs.length, "Mint: length must be equal");
        uint256[] memory _tokenIds = new uint256[](NFTsToBeCreate);
        for(uint256 i = 0; i < NFTsToBeCreate; i++) {
            uint256 _tokenId = _tokenIdTracker.current();
            _mint(_msgSender(), _tokenId);
            _setTokenURI(_tokenId, _tokenURIs[i]);
            _setTokenRoyalty(_tokenId, _royaltyFees, _royaltyReceivers);
            _tokenIdTracker.increment();
            _tokenIds[i] = _tokenId;
        }
        addToPack(_tokenIds);
        return true;
    }

    function addToPack(uint256[] memory _tokenIds) internal {
        require(_tokenIds.length > 0, "length must be greater than zero");
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(_exists(_tokenIds[i]),"non-exist token");
            require(!isPacked[_tokenIds[i]], "token already exist");
            isPacked[_tokenIds[i]] = true;
        }
        emit Pack(_tokenIds);
    }


    function removeFromPack(uint256[] memory _tokenIds) external onlyRole("OPERATOR_ROLE") {
        require(_tokenIds.length > 0, "length must be greater than zero");
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(_exists(_tokenIds[i]),"non-exist token");
            require(isPacked[_tokenIds[i]], "token already exist");
            isPacked[_tokenIds[i]] = false;
        }
        emit RemovedFromPack(_tokenIds);
    }



    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

   
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
   
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }


    function royaltyInfo(
        uint256 _tokenId, 
        uint256 price) 
        external 
        view 
        returns(uint96[] memory, address[] memory, uint256) {
        require(_exists(_tokenId),"ERC721Royalty: query for nonexistent token");
        require(price > 0, "ERC721Royalty: amount should be greater than zero");
        uint96[] memory royaltyFee = new uint96[](tokenRoyalty[_tokenId].royaltyPermiles.length); 
        address[] memory receivers = tokenRoyalty[_tokenId].receivers; 
        uint256 royalty;
        uint96[] memory _royaltyFees = tokenRoyalty[_tokenId].royaltyPermiles;
        for( uint96 i = 0; i < _royaltyFees.length; i++) {
            royaltyFee[i] = uint96(price * _royaltyFees[i] / 1000);
            royalty += royaltyFee[i];        
        }

        return (royaltyFee, receivers, royalty); 

    }

    

    function _setTokenRoyalty(
        uint256 _tokenId,
        uint96[] calldata royaltyFeePermiles,
        address[] calldata receivers
    ) internal {
        require(royaltyFeePermiles.length == receivers.length,"ERC721Royalty: length should be same");
        tokenRoyalty[_tokenId] = TokenRoyalty(royaltyFeePermiles, receivers);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


    function verifySign(
        string memory _tokenURI,
        address caller,
        Sign memory sign
    ) internal view {
        bytes32 hash = keccak256(
            abi.encodePacked(this, caller, _tokenURI, sign.nonce)
        );
        require(
            owner ==
                ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            hash
                        )
                    ),
                    sign.v,
                    sign.r,
                    sign.s
                ),
            "Owner sign verification failed"
        );
    }
}
