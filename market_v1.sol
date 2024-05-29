// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

error NotNftOwner(address nftOwner, address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error TooManyPicker(address nftAddress, uint256 tokenId);
error NotEnoughPicker(address nftAddress, uint256 tokenId);
error CanNotCancel(address nftAddress, uint256 tokenId);
error PickError(address nftAddress, uint256 tokenId, address picker, uint256 pickNum);
interface SoulcialCall {
    function creatorOf(uint256 tokenId) external view returns (address);
}
contract NftMarket is IERC721Receiver, ReentrancyGuard {
    uint constant PICK_NUM = 4;

    address _soulcialAdd = 0x478E3634aDdcCB19AE7E48AF92DdD575d46fE747;
    struct Listing {
        uint256 price;
        address seller;
        uint pickCount;
        address[] pickers;
        uint256[] pickVals;
        bool[] status;
    }  
    event ItemListed(address nftOwner, address nftAddress, uint256 tokenId, uint256 price);
    event ItemCanceled(address nftAddress, uint256 tokenId);
    event ItemPicked(address nftAddress, uint256 tokenId, address picker, uint256 pickNum);
    event ItemDeal(address nftAddress, uint256 tokenId, address buyer, uint8 buyer_index, uint256 sellerAmount, uint256 shareAmount);
    address _owner;
    mapping(address => mapping(uint256 => Listing)) private _nft_listings;
    modifier onlyOwner {
        require(msg.sender == _owner);
        _;
    }
    function getOfficialAddress() external view returns (address) {
        return _soulcialAdd;
    }
    function setOfficialAddress(address newAddress) external onlyOwner {
        _soulcialAdd = newAddress;
    }
    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    function withdrawOther(address add) external onlyOwner {
        payable(add).transfer(address(this).balance);
    }
    function getBalance() external view returns(uint256) {
        return address(this).balance;
    }
    modifier notListed(
        address nftAddress,
        uint256 tokenId
   ) {
        Listing memory listing = _nft_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }
    modifier isListed(
        address nftAddress, 
        uint256 tokenId
    ) {
        Listing memory listing = _nft_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }
    modifier canPick(
        address nftAddress, 
        uint256 tokenId,
        uint index
    ) {
        Listing memory listedItem = _nft_listings[nftAddress][tokenId];
        if (listedItem.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        if (listedItem.pickCount >= PICK_NUM) {
            revert TooManyPicker(nftAddress, tokenId);
        }
        if (index >= PICK_NUM) {
            revert PickError(nftAddress, tokenId, msg.sender, index);
        }
        if (listedItem.seller == msg.sender) {
            revert PickError(nftAddress, tokenId, msg.sender, index);
        }
        if (listedItem.status[index]) {
            revert PickError(nftAddress, tokenId, msg.sender, index);
        }
        for (uint256 i = 0; i < listedItem.pickers.length; i++) {
            if (listedItem.pickers[i] == msg.sender) {
                revert PickError(nftAddress, tokenId, msg.sender, index);
            }
        }
        if (msg.value < listedItem.price) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.price);
        }
        _;
    }
    modifier canDeal(
        address nftAddress, 
        uint256 tokenId
    ) {
        Listing memory listedItem = _nft_listings[nftAddress][tokenId];
        if (listedItem.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        if (listedItem.pickCount < PICK_NUM) {
            revert NotEnoughPicker(nftAddress, tokenId);
        }
        _;
    }
    modifier canCancel(
        address nftAddress, 
        uint256 tokenId
    ) {
        Listing memory listedItem = _nft_listings[nftAddress][tokenId];
        if (listedItem.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        if (listedItem.pickCount > 0) {
            revert CanNotCancel(nftAddress, tokenId);
        }
        _;
    }
    constructor() {      
        _owner = msg.sender;
    }
    function listItem(address nftAddress, uint256 tokenId, address nftOwner, uint256 price) 
        external
        onlyOwner 
        notListed(nftAddress, tokenId)
    {
        IERC721 nft = IERC721(nftAddress);
        address nftRealOwner = nft.ownerOf(tokenId);
        if (nftRealOwner != nftOwner) {
            revert NotNftOwner(nftOwner, nftAddress, tokenId);
        }
        nft.safeTransferFrom(nftRealOwner, address(this), tokenId);
        _nft_listings[nftAddress][tokenId] = this.getInitListing(price, nftRealOwner);
        emit ItemListed(nftRealOwner, nftAddress, tokenId, price);
    }
    function getInitListing(uint256 price, address nftRealOwner) external view returns(Listing memory) {
        Listing memory listing = Listing({
            price: price,
            seller: nftRealOwner,
            pickCount: 0,
            pickers: new address[](PICK_NUM),
            pickVals: new uint256[](PICK_NUM),
            status: new bool[](PICK_NUM)
        });
        return listing;
    }
    function cancelListing(address nftAddress, uint256 tokenId)
        external
        onlyOwner
        canCancel(nftAddress, tokenId)
    {
        IERC721 nft = IERC721(nftAddress);
        Listing storage listedItem = _nft_listings[nftAddress][tokenId];
        nft.safeTransferFrom(address(this), listedItem.seller, tokenId);
        delete (_nft_listings[nftAddress][tokenId]);
        emit ItemCanceled(nftAddress, tokenId);
    }
    function pickItem(address nftAddress, uint256 tokenId, uint256 index) 
        external
        payable
        isListed(nftAddress, tokenId)
        canPick(nftAddress, tokenId, index)
        nonReentrant
    {
        Listing storage listedItem = _nft_listings[nftAddress][tokenId];
        listedItem.pickers[index] = msg.sender;
        listedItem.pickVals[index] = msg.value;
        listedItem.pickCount += 1;
        listedItem.status[index] = true;

        emit ItemPicked(nftAddress, tokenId, msg.sender, index);
    }

    function dealList(address nftAddress, uint256 tokenId) 
        external
        nonReentrant
        canDeal(nftAddress, tokenId)
        onlyOwner
    {
        Listing memory listedItem = _nft_listings[nftAddress][tokenId];
        uint8 buyer_index = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number-1), nftAddress, tokenId))) % PICK_NUM);
        address targetBuyer = listedItem.pickers[buyer_index];
        uint256 targetVal = listedItem.pickVals[buyer_index];
        
        IERC721 nft = IERC721(nftAddress);
        address nftOwner = nft.ownerOf(tokenId);
        if (address(this) != nftOwner) {
            revert NotNftOwner(address(this), nftAddress, tokenId);
        }
        nft.safeTransferFrom(address(this), targetBuyer, tokenId);
        uint256 sellerAmount = ( targetVal * 80 ) / 100;
        uint256 shareAmount = (targetVal - sellerAmount) / 5;
        payable(listedItem.seller).transfer(sellerAmount);
        address creator = getCreatorFrom(nftAddress, tokenId);
        payable(creator).transfer(shareAmount);
        payable(_soulcialAdd).transfer(shareAmount);
        for (uint256 i = 0; i < PICK_NUM; i++) {
            if (i != buyer_index) {
                payable(listedItem.pickers[i]).transfer(shareAmount + listedItem.pickVals[i]);
            }
        }
        delete (_nft_listings[nftAddress][tokenId]);
        
        emit ItemDeal(nftAddress, tokenId, targetBuyer, buyer_index, sellerAmount, shareAmount);
    }   
    function getCreatorFrom(address nftAddress, uint256 tokenId) internal view returns(address creator) {
        creator = SoulcialCall(nftAddress).creatorOf(tokenId);
    }
   function getListing(address nftAddress, uint256 tokenId) external view returns(Listing memory listedItem) {
    Listing storage item = _nft_listings[nftAddress][tokenId];
    return Listing({
        price: item.price,
        seller: item.seller,
        pickCount: item.pickCount,
        pickers: item.pickers,
        pickVals: item.pickVals,
        status: item.status
    });
}
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        return this.onERC721Received.selector;
    } 
}