// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RealEstatePool is Ownable {
    using SafeMath for uint256;

    struct Property {
        address owner;
        uint256 totalShares;
        uint256 availableShares;
        uint256 rentalPayment;
        uint256 propertyValue;
        mapping(address => uint256) balances;
    }

    mapping(uint256 => Property) private properties;
    uint256 private nextPropertyId;

    bool public isObsolete;

    uint256 public annualRentUpdateTimestamp;
    uint256 public annualRentUpdateAmount;

    event PropertyRegistered(uint256 indexed propertyId, address indexed owner, uint256 totalShares, uint256 propertyValue);
    event SharesPurchased(uint256 indexed propertyId, address indexed buyer, uint256 sharesAmount, uint256 amountPaid);
    event SharesSold(uint256 indexed propertyId, address indexed seller, uint256 sharesAmount, uint256 amountReceived);
    event RentalPaymentReceived(uint256 indexed propertyId, uint256 amount);
    event DividendsDistributed(uint256 indexed propertyId, uint256 amount);
    event ContractObsoleted();
    event AnnualRentUpdate(uint256 newRentAmount);

    modifier onlyActive() {
        require(!isObsolete, "Contract is obsolete and no longer active");
        _;
    }

    constructor() {
        annualRentUpdateTimestamp = block.timestamp;
    }

    function registerProperty(uint256 totalShares, uint256 rentalPayment, uint256 propertyValue) external onlyOwner onlyActive {
        require(totalShares > 0, "Total shares must be greater than zero");
        require(rentalPayment > 0, "Rental payment must be greater than zero");
        require(propertyValue > 0, "Property value must be greater than zero");

        Property storage newProperty = properties[nextPropertyId];
        newProperty.owner = msg.sender;
        newProperty.totalShares = totalShares;
        newProperty.availableShares = totalShares;
        newProperty.rentalPayment = rentalPayment;
        newProperty.propertyValue = propertyValue;

        emit PropertyRegistered(nextPropertyId, msg.sender, totalShares, propertyValue);
        nextPropertyId++;
    }

    function purchaseShares(uint256 propertyId, uint256 numberShares) external payable onlyActive {
        Property storage property = properties[propertyId];
        require(property.owner != address(0), "Property does not exist");
        require(numberShares > 0, "Shares amount must be greater than zero");
        require(numberShares <= property.availableShares, "Not enough shares available");

        uint256 shareValue = calculateShareValue(propertyId);
        uint256 amountPaid = numberShares * shareValue;
        require(msg.value >= amountPaid, "Insufficient payment amount");

        property.balances[msg.sender] = property.balances[msg.sender].add(numberShares);
        property.availableShares = property.availableShares.sub(numberShares);

        if (msg.value > amountPaid) {
            payable(msg.sender).transfer(msg.value.sub(amountPaid));
        }

        emit SharesPurchased(propertyId, msg.sender, numberShares, amountPaid);
    }

    function sellShares(uint256 propertyId, uint256 sharesAmount) external onlyActive {
        Property storage property = properties[propertyId];
        require(property.owner != address(0), "Property does not exist");
        require(sharesAmount > 0, "Shares amount must be greater than zero");
        require(property.balances[msg.sender] >= sharesAmount, "Insufficient shares balance");

        uint256 shareValue = calculateShareValue(propertyId);
        uint256 amountReceived = shareValue.mul(sharesAmount);

        property.balances[msg.sender] = property.balances[msg.sender].sub(sharesAmount);
        property.availableShares = property.availableShares.add(sharesAmount);

        payable(msg.sender).transfer(amountReceived);

        emit SharesSold(propertyId, msg.sender, sharesAmount, amountReceived);
    }

    function receiveRentalPayment(uint256 propertyId) external payable onlyOwner onlyActive {
        Property storage property = properties[propertyId];
        require(property.owner != address(0), "Property does not exist");
        require(msg.value == property.rentalPayment.mul(property.availableShares), "Incorrect rental payment amount");

        emit RentalPaymentReceived(propertyId, msg.value);
    }

    function distributeDividends(uint256 propertyId) external onlyOwner onlyActive {
        Property storage property = properties[propertyId];
        require(property.availableShares > 0, "No shares available");

        uint256 dividendAmount = address(this).balance.div(property.totalShares);
        for (uint256 i = 0; i < property.totalShares; i++) {
            address shareholder = getShareholderAtIndex(propertyId, i);
            uint256 shareAmount = dividendAmount.mul(property.balances[shareholder]);
            payable(shareholder).transfer(shareAmount);
        }

        emit DividendsDistributed(propertyId, address(this).balance);
    }

    function updateAnnualRent(uint256 newRentAmount) external onlyOwner onlyActive {
        require(block.timestamp > annualRentUpdateTimestamp, "Rent update can only occur once per year");
        require(newRentAmount > 0, "New rent amount must be greater than zero");

        annualRentUpdateTimestamp = block.timestamp;
        annualRentUpdateAmount = newRentAmount;

        emit AnnualRentUpdate(newRentAmount);
    }

    function obsoleted() external onlyOwner {
        isObsolete = true;
        emit ContractObsoleted();
    }

    function getPropertyDetails(uint256 propertyId)
        external
        view
        returns (
            address _owner,
            uint256 totalShares,
            uint256 availableShares,
            uint256 rentalPayment,
            uint256 propertyValue
        )
    {
        Property storage property = properties[propertyId];
        require(property.owner != address(0), "Property does not exist");

        return (property.owner, property.totalShares, property.availableShares, property.rentalPayment, property.propertyValue);
    }

    function getShareholderAtIndex(uint256 propertyId, uint256 index) private view returns (address) {
        Property storage property = properties[propertyId];
        uint256 count = 0;
        for (uint256 i = 0; i < property.totalShares; i++) {
            address shareholder = address(uint160(i));
            if (property.balances[shareholder] > 0) {
                if (count == index) {
                    return shareholder;
                }
                count++;
            }
        }
        revert("Invalid index");
    }

    function calculateShareValue(uint256 propertyId) public view returns (uint256) {
        Property storage property = properties[propertyId];
        require(property.owner != address(0), "Property does not exist");

        return property.propertyValue.div(property.totalShares);
    }
}
