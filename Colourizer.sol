// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title NostalgicPhotoColorizer
 * @dev A smart contract for colorizing black and white photos using AI and manual adjustments
 * @notice This contract handles photo submissions, AI colorization requests, and NFT minting
 */
contract NostalgicPhotoColorizer is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _photoIdCounter;
    
    // Events
    event PhotoSubmitted(uint256 indexed photoId, address indexed owner, string originalImageHash);
    event ColorizationRequested(uint256 indexed photoId, address indexed requester, uint256 fee);
    event ColorizationCompleted(uint256 indexed photoId, string colorizedImageHash, address indexed processor);
    event ManualAdjustmentMade(uint256 indexed photoId, address indexed adjuster, string adjustmentData);
    event PhotoNFTMinted(uint256 indexed tokenId, uint256 indexed photoId, address indexed owner);
    event ProcessorRegistered(address indexed processor, string modelHash);
    event FeeUpdated(uint256 newFee);
    
    // Structs
    struct Photo {
        uint256 id;
        address owner;
        string originalImageHash; // IPFS hash of original B&W photo
        string colorizedImageHash; // IPFS hash of AI colorized photo
        string finalImageHash; // IPFS hash after manual adjustments
        uint256 submissionTime;
        uint256 colorizationTime;
        PhotoStatus status;
        uint256 processingFee;
        address processor;
        bool isNFTMinted;
        uint256 nftTokenId;
    }
    
    struct ColorAdjustment {
        uint256 photoId;
        address adjuster;
        string adjustmentData; // JSON string containing color adjustment parameters
        uint256 timestamp;
    }
    
    struct AIProcessor {
        address processorAddress;
        string modelHash; // Hash of the AI model used
        uint256 totalProcessed;
        uint256 reputation; // Rating out of 100
        bool isActive;
        uint256 registrationTime;
    }
    
    enum PhotoStatus {
        Submitted,
        InProcessing,
        AIColorized,
        ManuallyAdjusted,
        Completed,
        NFTMinted
    }
    
    // State variables
    mapping(uint256 => Photo) public photos;
    mapping(uint256 => ColorAdjustment[]) public photoAdjustments;
    mapping(address => AIProcessor) public aiProcessors;
    mapping(address => uint256[]) public userPhotos;
    
    address[] public registeredProcessors;
    uint256 public colorizationFee = 0.01 ether;
    uint256 public adjustmentFee = 0.005 ether;
    uint256 public nftMintingFee = 0.02 ether;
    
    // Modifiers
    modifier onlyPhotoOwner(uint256 _photoId) {
        require(photos[_photoId].owner == msg.sender, "Not the photo owner");
        _;
    }
    
    modifier onlyRegisteredProcessor() {
        require(aiProcessors[msg.sender].isActive, "Not a registered AI processor");
        _;
    }
    
    modifier photoExists(uint256 _photoId) {
        require(photos[_photoId].id != 0, "Photo does not exist");
        _;
    }
    
    constructor() ERC721("NostalgicPhotoColorizer", "NPC") Ownable(msg.sender) {}
    
    /**
     * @dev Submit a black and white photo for colorization
     * @param _originalImageHash IPFS hash of the original B&W photo
     */
    function submitPhoto(string memory _originalImageHash) external payable nonReentrant {
        require(bytes(_originalImageHash).length > 0, "Invalid image hash");
        require(msg.value >= colorizationFee, "Insufficient fee");
        
        _photoIdCounter.increment();
        uint256 newPhotoId = _photoIdCounter.current();
        
        photos[newPhotoId] = Photo({
            id: newPhotoId,
            owner: msg.sender,
            originalImageHash: _originalImageHash,
            colorizedImageHash: "",
            finalImageHash: "",
            submissionTime: block.timestamp,
            colorizationTime: 0,
            status: PhotoStatus.Submitted,
            processingFee: msg.value,
            processor: address(0),
            isNFTMinted: false,
            nftTokenId: 0
        });
        
        userPhotos[msg.sender].push(newPhotoId);
        
        emit PhotoSubmitted(newPhotoId, msg.sender, _originalImageHash);
        emit ColorizationRequested(newPhotoId, msg.sender, msg.value);
    }
    
    /**
     * @dev AI processor submits colorized version of the photo
     * @param _photoId ID of the photo to colorize
     * @param _colorizedImageHash IPFS hash of the colorized photo
     */
    function submitColorization(
        uint256 _photoId, 
        string memory _colorizedImageHash
    ) external onlyRegisteredProcessor photoExists(_photoId) nonReentrant {
        Photo storage photo = photos[_photoId];
        require(photo.status == PhotoStatus.Submitted, "Photo not available for processing");
        require(bytes(_colorizedImageHash).length > 0, "Invalid colorized image hash");
        
        photo.colorizedImageHash = _colorizedImageHash;
        photo.finalImageHash = _colorizedImageHash; // Initially same as AI colorized
        photo.colorizationTime = block.timestamp;
        photo.status = PhotoStatus.AIColorized;
        photo.processor = msg.sender;
        
        // Pay the processor
        uint256 processorPayment = (photo.processingFee * 70) / 100; // 70% to processor
        payable(msg.sender).transfer(processorPayment);
        
        // Update processor stats
        aiProcessors[msg.sender].totalProcessed++;
        
        emit ColorizationCompleted(_photoId, _colorizedImageHash, msg.sender);
    }
    
    /**
     * @dev Allow photo owner to make manual color adjustments
     * @param _photoId ID of the photo to adjust
     * @param _adjustmentData JSON string containing adjustment parameters
     * @param _finalImageHash IPFS hash of the manually adjusted photo
     */
    function makeColorAdjustment(
        uint256 _photoId,
        string memory _adjustmentData,
        string memory _finalImageHash
    ) external payable onlyPhotoOwner(_photoId) photoExists(_photoId) nonReentrant {
        require(msg.value >= adjustmentFee, "Insufficient adjustment fee");
        require(photos[_photoId].status >= PhotoStatus.AIColorized, "Photo not ready for adjustments");
        require(bytes(_adjustmentData).length > 0, "Invalid adjustment data");
        require(bytes(_finalImageHash).length > 0, "Invalid final image hash");
        
        Photo storage photo = photos[_photoId];
        photo.finalImageHash = _finalImageHash;
        photo.status = PhotoStatus.ManuallyAdjusted;
        
        // Store adjustment details
        photoAdjustments[_photoId].push(ColorAdjustment({
            photoId: _photoId,
            adjuster: msg.sender,
            adjustmentData: _adjustmentData,
            timestamp: block.timestamp
        }));
        
        emit ManualAdjustmentMade(_photoId, msg.sender, _adjustmentData);
    }
    
    /**
     * @dev Mint NFT of the colorized photo
     * @param _photoId ID of the photo to mint as NFT
     * @param _tokenURI Metadata URI for the NFT
     */
    function mintPhotoNFT(
        uint256 _photoId, 
        string memory _tokenURI
    ) external payable onlyPhotoOwner(_photoId) photoExists(_photoId) nonReentrant {
        require(msg.value >= nftMintingFee, "Insufficient minting fee");
        require(!photos[_photoId].isNFTMinted, "NFT already minted for this photo");
        require(photos[_photoId].status >= PhotoStatus.AIColorized, "Photo not ready for NFT minting");
        
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);
        
        photos[_photoId].isNFTMinted = true;
        photos[_photoId].nftTokenId = newTokenId;
        photos[_photoId].status = PhotoStatus.NFTMinted;
        
        emit PhotoNFTMinted(newTokenId, _photoId, msg.sender);
    }
    
    /**
     * @dev Register as an AI processor
     * @param _modelHash Hash of the AI model being used
     */
    function registerAsProcessor(string memory _modelHash) external {
        require(bytes(_modelHash).length > 0, "Invalid model hash");
        require(!aiProcessors[msg.sender].isActive, "Already registered");
        
        aiProcessors[msg.sender] = AIProcessor({
            processorAddress: msg.sender,
            modelHash: _modelHash,
            totalProcessed: 0,
            reputation: 50, // Start with neutral reputation
            isActive: true,
            registrationTime: block.timestamp
        });
        
        registeredProcessors.push(msg.sender);
        
        emit ProcessorRegistered(msg.sender, _modelHash);
    }
    
    /**
     * @dev Update processor reputation (only owner)
     * @param _processor Address of the processor
     * @param _newReputation New reputation score (0-100)
     */
    function updateProcessorReputation(address _processor, uint256 _newReputation) external onlyOwner {
        require(aiProcessors[_processor].isActive, "Processor not registered");
        require(_newReputation <= 100, "Reputation must be <= 100");
        
        aiProcessors[_processor].reputation = _newReputation;
    }
    
    /**
     * @dev Get photo details
     * @param _photoId ID of the photo
     */
    function getPhoto(uint256 _photoId) external view photoExists(_photoId) returns (Photo memory) {
        return photos[_photoId];
    }
    
    /**
     * @dev Get user's photos
     * @param _user Address of the user
     */
    function getUserPhotos(address _user) external view returns (uint256[] memory) {
        return userPhotos[_user];
    }
    
    /**
     * @dev Get photo adjustments history
     * @param _photoId ID of the photo
     */
    function getPhotoAdjustments(uint256 _photoId) external view returns (ColorAdjustment[] memory) {
        return photoAdjustments[_photoId];
    }
    
    /**
     * @dev Update fees (only owner)
     */
    function updateFees(
        uint256 _colorizationFee,
        uint256 _adjustmentFee,
        uint256 _nftMintingFee
    ) external onlyOwner {
        colorizationFee = _colorizationFee;
        adjustmentFee = _adjustmentFee;
        nftMintingFee = _nftMintingFee;
        
        emit FeeUpdated(_colorizationFee);
    }
    
    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev Emergency pause processor (only owner)
     */
    function pauseProcessor(address _processor) external onlyOwner {
        aiProcessors[_processor].isActive = false;
    }
    
    /**
     * @dev Reactivate processor (only owner)
     */
    function reactivateProcessor(address _processor) external onlyOwner {
        require(aiProcessors[_processor].processorAddress != address(0), "Processor not registered");
        aiProcessors[_processor].isActive = true;
    }
    
    // Override functions required by Solidity
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
