// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "operator-filter-registry/src/DefaultOperatorFilterer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/StartTokenIdHelper.sol";
import "./utils/ERC4907A.sol";
import "./utils/Recoverable.sol";

interface ITraits {
    function contractURI() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract ThisIsSpartaWtfNft is
    ERC721A,
    StartTokenIdHelper,
    ERC721AQueryable,
    ERC4907A,
    ERC2981,
    DefaultOperatorFilterer,
    ReentrancyGuard,
    Ownable,
    Recoverable
{
    // Constants
    uint256 private constant _MAX_SUPPLY = 300_000;
    uint256 private constant _FREE_MINT_LIMIT = 10_000;
    uint256 private constant _MINT_LIMIT = 100;

    // Metadata
    string private constant _name = "This is $SPARTA!";
    string private constant _symbol = "SPARTAN";
    bool private _revealed;
    string private _notRevealedURI;
    string private _contractURI;
    string private _baseUri;
    string private _baseExt;

    address public traits;
    address public battle;
    address payable public fund;
    bool isFrozen;

    uint256 private _totalFreeMinted;

    // Errors
    error MaxFreeMintLimit();
    error MaxSupplyLimit();
    error MaxMintLimit();
    error WrongValue();

    constructor(
        address royaltyReceiver,
        uint96 royaltyNumerator
    ) ERC721A(_name, _symbol) StartTokenIdHelper(1) {
        _setDefaultRoyalty(royaltyReceiver, royaltyNumerator);
    }

    function freeMint(uint256 quantity) external nonReentrant {
        if (_totalFreeMinted + quantity > _FREE_MINT_LIMIT) {
            revert MaxFreeMintLimit();
        }
        if (_numberMinted(_msgSender()) + quantity > _MINT_LIMIT) {
            revert MaxMintLimit();
        }
        _totalFreeMinted += quantity;
        _safeMint(_msgSender(), quantity);
    }

    function mint(uint256 quantity) external payable nonReentrant {
        if (_totalMinted() + quantity > _MAX_SUPPLY) {
            revert MaxSupplyLimit();
        }
        if (quantity > _MINT_LIMIT) {
            revert MaxMintLimit();
        }
        if (msg.value / quantity != 0.01 ether) {
            revert WrongValue();
        }
        _transferEth(address(this).balance, fund);
        _safeMint(_msgSender(), quantity);
    }

    function totalFreeMinted() external view returns (uint256) {
        return _totalFreeMinted;
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    function totalBurned() external view returns (uint256) {
        return _totalBurned();
    }

    function mintedOf(address owner) external view returns (uint256) {
        return _numberMinted(owner);
    }

    function burnedOf(address owner) external view returns (uint256) {
        return _numberBurned(owner);
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function getOwnershipAt(
        uint256 index
    ) external view returns (TokenOwnership memory) {
        return _ownershipAt(index);
    }

    function getOwnershipOf(
        uint256 index
    ) external view returns (TokenOwnership memory) {
        return _ownershipOf(index);
    }

    function initializeOwnershipAt(uint256 index) external {
        _initializeOwnershipAt(index);
    }

    // ERC4907A extra
    function explicitUserOf(uint256 tokenId) external view returns (address) {
        return _explicitUserOf(tokenId);
    }

    // Metadata
    function reveal() external onlyOwner {
        _revealed = true;
    }

    function setNotRevealedURI(string memory uri_) external onlyOwner {
        _notRevealedURI = uri_;
    }

    function contractURI() external view returns (string memory) {
        if (traits != address(0)) return ITraits(traits).contractURI();
        return _contractURI;
    }

    function setContractURI(string memory uri_) external onlyOwner {
        _contractURI = uri_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721A, IERC721A) returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (!_revealed) return _notRevealedURI;

        if (traits != address(0)) return ITraits(traits).tokenURI(tokenId);

        return
            bytes(_baseUri).length != 0
                ? string(
                    abi.encodePacked(_baseUri, _toString(tokenId), _baseExt)
                )
                : "";
    }

    function baseURI() external view returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory uri_) external onlyOwner {
        _baseUri = uri_;
    }

    function setBaseExtension(string memory fileExtension) external onlyOwner {
        _baseExt = fileExtension;
    }

    function setTraits(address traits_) external onlyOwner {
        require(!isFrozen, "Frozen");
        traits = traits_;
    }

    function setFreeze() external onlyOwner {
        isFrozen = true;
    }

    function setFund(address payable fund_) external onlyOwner {
        require(!isFrozen, "Frozen");
        fund = fund_;
    }

    // Battles
    function setBattle(address battle_) external onlyOwner {
        require(!isFrozen, "Frozen");
        battle = battle_;
    }

    modifier onlyBattle() {
        require(battle == _msgSender(), "Caller is not the battle");
        _;
    }

    function burn(uint256 tokenId) external onlyBattle {
        _burn(tokenId, false);
    }

    // Royalty
    function setDefaultRoyalty(
        address royaltyReceiver,
        uint96 royaltyNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(royaltyReceiver, royaltyNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    // IERC721Enumerable
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256 tokenId) {
        uint256 balance = balanceOf(owner);
        if (balance <= index) {
            revert("ERC721Enumerable: owner index out of bounds");
        }

        unchecked {
            uint256 tokenIdsIdx;
            address currOwnershipAddr;
            TokenOwnership memory ownership;
            for (uint256 i = _startTokenId(); tokenIdsIdx != balance; ++i) {
                ownership = _ownershipAt(i);
                if (ownership.burned) {
                    continue;
                }
                if (ownership.addr != address(0)) {
                    currOwnershipAddr = ownership.addr;
                }
                if (currOwnershipAddr == owner) {
                    if (tokenIdsIdx == index) {
                        return i;
                    }
                    tokenIdsIdx++;
                }
            }
        }
    }

    function tokenByIndex(
        uint256 index
    ) external view returns (uint256 tokenId) {
        tokenId = _startTokenId() + index;
        if (tokenId < _nextTokenId()) {
            return tokenId;
        }
        revert("ERC721Enumerable: global index out of bounds");
    }

    // Overrides
    function _startTokenId() internal view override returns (uint256) {
        return startTokenId();
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override(ERC721A, ERC4907A) {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721A, IERC721A) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    )
        public
        payable
        override(ERC721A, IERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721A, IERC721A, ERC4907A, ERC2981)
        returns (bool)
    {
        // IERC721Enumerable - 0x780e9d63
        return
            interfaceId == 0x780e9d63 || super.supportsInterface(interfaceId);
    }
}
