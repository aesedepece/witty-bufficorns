// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "witnet-solidity-bridge/contracts/UsingWitnet.sol";
import "witnet-solidity-bridge/contracts/interfaces/IWitnetRandomness.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IWittyBufficornsAdmin.sol";
import "./interfaces/IWittyBufficornsEvents.sol";
import "./interfaces/IWittyBufficornsSurrogates.sol";
import "./interfaces/IWittyBufficornsView.sol";

import "./interfaces/IWittyBufficornsDecorator.sol";

/// @title Witty Bufficorns Awards - ERC721 Token contract
/// @author Otherplane Labs, 2022.
contract WittyBufficornsToken
    is
        ERC721,
        Ownable,
        ReentrancyGuard,
        IWittyBufficornsAdmin,
        IWittyBufficornsEvents,
        IWittyBufficornsSurrogates,
        IWittyBufficornsView
{
    using Strings for uint256;
    using WittyBufficornsLib for WittyBufficornsLib.Storage;

    IWitnetRandomness public immutable randomizer;
    WitnetRequestBoard public immutable witnet;

    modifier inStatus(WittyBufficornsLib.Status status) {
        require(
            __storage.status() == status,
            "WittyBufficornsToken: bad mood"
        );
        _;
    }

    modifier onlySignator {
        require(
            msg.sender == __storage.signator,
            "WittyBufficornsToken: only signator"
        );
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        require(
            _exists(_tokenId),
            "WittyBufficornsToken: inexistent token"
        );
        _;
    }

    WittyBufficornsLib.Storage internal __storage;

    constructor(
            string memory _name,
            string memory _symbol,
            IWitnetRandomness _randomizer,
            IWittyBufficornsDecorator _decorator
        )
        ERC721(_name, _symbol)
    {
        randomizer = _randomizer;
        witnet = UsingWitnet(address(_randomizer)).witnet();
        setDecorator(address(_decorator));
        __storage.signator = msg.sender;
    }

    receive() external payable {}


    // ========================================================================
    // --- 'ERC721Metadata' overriden functions -------------------------------
    
    function baseURI()
        public view
        virtual
        returns (string memory)
    {
        return IWittyBufficornsDecorator(__storage.decorator).baseURI();
    }
    
    function metadata(uint256 _tokenId)
        external view
        virtual
        tokenExists(_tokenId)
        returns (string memory)
    {
        return toJSON(_tokenId);
    }

    function tokenURI(uint256 _tokenId)
        public view
        virtual override
        tokenExists(_tokenId)
        returns (string memory)
    {
        return string(abi.encodePacked(
            baseURI(),
            _tokenId.toString()
        ));
    }

    // ========================================================================
    // --- Implementation of 'IWittyBufficornsAdmin' --------------------------

    /// Returns decorator contract's address.
    function getDecorator()
        external view
        virtual override
        returns (address)
    {
        return __storage.decorator;
    }

    /// Returns signator's address.
    function getSignator()
        external view
        returns (address)
    {
        return __storage.signator;
    }

    /// Returns tender's current status
    function getStatus()
        external view
        returns (WittyBufficornsLib.Status)
    {
        return __storage.status();
    }

    /// Sets name, ranch and final traits for the given bufficorn.
    /// @dev Must be called from the signators's address.
    /// @dev Fails if not in Breeding status. 
    function setBufficorn(
            uint256 _id,
            uint256 _ranchId,
            string calldata _name,
            uint256[6] calldata _traits
        )
        external
        onlySignator
        inStatus(WittyBufficornsLib.Status.Breeding)
    {
        WittyBufficornsLib.Ranch storage __ranch = __storage.ranches[_ranchId];
        require(
            bytes(__ranch.name).length > 0,
            "WittyBufficornsToken: inexistent ranch"
        );
        require(
            bytes(_name).length > 0,
            "WittyBufficornsToken: no name"
        );
        WittyBufficornsLib.Bufficorn storage __bufficorn = __storage.bufficorns[_id];
        if (bytes(_name).length > 0) {
            if (bytes(__bufficorn.name).length == 0) {
                __storage.stats.totalBufficorns ++;
            }
        }
        uint _score = _traits[0];
        for (uint _i = 1; _i < 6; _i ++) {
            if (_traits[_i] < _score) {
                // Bufficorn's score correspond to the minimum or its traits
                _score = _traits[_i];
            }
        }
        require( 
            _score >= __ranch.score,
            "WittyBufficornsToken: score below ranch'es"
        );
        __bufficorn.name = _name;
        __bufficorn.ranchId = _ranchId;
        __bufficorn.score = _score;
        __bufficorn.traits = _traits;
        emit BufficornSet(_id, _name, _score, _traits);
    }

    /// Sets Opensea-compliant Decorator contract
    /// @dev Must be called from the owner's address.
    function setDecorator(address _decorator)
        public
        virtual override
        onlyOwner
    {
        require(
            address(_decorator) != address(0),
            "WittyBufficornsToken: no decorator"
        );
        __storage.decorator = _decorator;
        emit DecoratorSet(_decorator);
    }

    /// Sets a ranch's data, final score and weather station.
    /// @dev Must be called from the signators's address.
    /// @dev Fails if not in Breeding status. 
    function setRanch(
            uint256 _id,
            uint256 _score,
            string calldata _name,
            bytes4 _weatherStationAscii
        )
        external
        onlySignator
        inStatus(WittyBufficornsLib.Status.Breeding)
    {
        require(
            bytes(_name).length > 0,
            "WittyBufficornsToken: no name"
        );
        WittyBufficornsLib.Ranch storage __ranch = __storage.ranches[_id];
        if (bytes(_name).length > 0) {
            if (bytes(__ranch.name).length == 0) {
                // Increase ranches count if first time set
                __storage.stats.totalRanches ++;
            }
        }
        if (_weatherStationAscii != __ranch.weatherStationAscii) {
            /** Javascript DSL:
             *
             *  import * as Witnet from "witnet-requests"
             *  const weather = new Witnet.Source("https://api.weather.gov/stations/<code>/observations/latest")
             *    .parseJSONMap()
             *    .getMap("properties")
             *    .getString("textDescription")
             *
             *  const weatherRequest = new WitnetRequest()
             *    .addSource(weather)
             *    .setAggregator(new Witnet.Aggregator({ reducer: Witnet.Types.REDUCERS.mode }))
             *    .setTally(new Witnet.Aggregator({ reducer: Witnet.Types.REDUCERS.mode }))
             *    .setQuorum(10, 51) // set witness count and minimum consensus percentage
             *    .setFees(10 ** 6, 10 ** 6) // set Witnet economic incentives
             *    .setCollateral(5 * 10 ** 9) // set 5 wits as collateral
             */
            __ranch.witnet.request = new WitnetRequest(abi.encode(
                hex"0a6d12630801123968747470733a2f2f6170692e776561746865722e676f762f73746174696f6e732f",
                _weatherStationAscii,
                hex"2f6f62736572766174696f6e732f6c61746573741a248318778218666a70726f706572746965738218676f746578744465736372697074696f6e1a02",
                hex"10022202100210c0843d180a20c0843d28333080e497d012"
            ));
        }
        __ranch.name = _name;
        __ranch.score = _score;
        __ranch.weatherStationAscii = _weatherStationAscii;
        emit RanchSet(_id, _name, _score, _weatherStationAscii);
    }

    /// Sets externally owned account that is authorized to sign farmer awards.
    /// @dev Must be called from the owner's address.
    /// @dev Fails if not in Breeding status. 
    function setSignator(address _signator)
        public
        virtual override
        onlyOwner
        inStatus(WittyBufficornsLib.Status.Breeding)
    {
        require(
            _signator != address(0),
            "WittyBufficornsToken: no signator"
        );
        __storage.signator = _signator;        
        emit SignatorSet(_signator);
    }

    /// Stops Breeding phase, which means: (a) ranches and bufficorns' traits cannot be modified any more;
    /// and (b), randomness will be requested to the Witnet's oracle. 
    /// @param _totalRanches Total of ranches that must have been previously set.
    /// @param _totalBufficorns Total of bufficorns that must have been previoustly set.
    /// @dev Must be called from the Signator's address. Fails if not in Breeding status. 
    /// @dev If no WitnetRandomness address was provided in construction, contract status will directly change to Awarding.
    function stopBreeding(
            uint256 _totalRanches,
            uint256 _totalBufficorns
        )
        external payable
        virtual override
        onlySignator
        inStatus(WittyBufficornsLib.Status.Breeding)
    {
        require(
            __storage.stats.totalRanches == _totalRanches,
            "WittyBufficornsToken: ranches mismatch"
        );
        require(
            __storage.stats.totalBufficorns == _totalBufficorns,
            "WittyBufficornsToken: bufficorns mismatch"
        );
        __storage.stopBreedingBlock = block.number;
        if (address(randomizer) == address(0)) {
            __storage.stopBreedingRandomness = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            emit AwardingBegins(
                msg.sender,
                _totalRanches,
                _totalBufficorns
            );
        } else {
            uint _usedFunds = randomizer.randomize{value: msg.value}();
            if (_usedFunds < msg.value) {
                payable(msg.sender).transfer(msg.value - _usedFunds);
            }
        }
    }

    /// Starts the Awarding phase, in which players will be able to mint their tokens.
    /// @dev Must be called from the Signator's address. Fails if not in Randomizing status. 
    function startAwarding()
        external
        virtual override
        onlySignator
        inStatus(WittyBufficornsLib.Status.Randomizing)
    {
        __storage.stopBreedingRandomness = randomizer.getRandomnessAfter(__storage.stopBreedingBlock);
        emit AwardingBegins(
            msg.sender,
            __storage.stats.totalRanches,
            __storage.stats.totalBufficorns
        );
    }

    /// Ask the Witnet oracle to update current weather for the given ranch.
    function updateRanchWeather(uint256 _ranchId)
        external payable
        virtual override
        returns (uint256 _usedFunds)
    {
        WittyBufficorns.Ranch storage __ranch = __storage.ranches[_ranchId];
        if (address(__ranch.witnet.request) != address(0)) {
            uint _lastValidQueryId = __ranch.witnet.lastValidQueryId;
            uint _latestQueryId = __ranch.witnet.latestQueryId;            
            // Check whether there's no previous request pending to be solved:
            Witnet.QueryStatus _latestQueryStatus = witnet.getQueryStatus(_latestQueryId);
            if (_latestQueryId == 0 || _latestQueryStatus != Witnet.QueryStatus.Posted) {
                if (_latestQueryId > 0 && _latestQueryStatus == Witnet.QueryStatus.Reported) {
                    Witnet.Result memory _latestResult  = witnet.readResponseResult(_latestQueryId);
                    if (_latestResult.success) {
                        // If latest request was solved with no errors...
                        if (_lastValidQueryId > 0) {
                            // ... delete last valid response, if any
                            witnet.deleteQuery(_lastValidQueryId);
                        }
                        // ... and set latest request id as last valid request id.
                        __ranch.witnet.lastValidQueryId = _latestQueryId;
                    }
                }
                // Estimate request fee, in native currency:
                _usedFunds = witnet.estimateReward(tx.gasprice);
                
                // Post weather update request to the WitnetRequestBoard contract:
                __ranch.witnet.latestQueryId = witnet.postRequest{value: _usedFunds}(__ranch.witnet.request);
                
                if (_usedFunds < msg.value) {
                    // Transfer back unused funds, if any:
                    payable(msg.sender).transfer(msg.value - _usedFunds);
                }
            }
        }
    }


    // ========================================================================
    // --- Implementation of 'IWittyBufficornsSurrogates' ---------------------

    function mintFarmerAwards(
            address _tokenOwner,
            uint256 _ranchId,
            uint256 _farmerId,
            uint256 _farmerScore,
            string memory _farmerName,
            WittyBufficornsLib.Award[] calldata _farmerAwards,
            bytes memory _signature
        )
        public
        virtual override
        nonReentrant
        inStatus(WittyBufficorns.Status.Awarding)
    {
        require(_tokenOwner != address(0), "WittyBufficornsToken: no token owner");
        require(_farmerAwards.length > 0, "WittyBufficornsToken: no awards");

        WittyBufficorns.Ranch storage __ranch = __storage.ranches[_ranchId];
        require(__ranch.score > 0, "WittyBufficornsToken: inexistent ranch");

        WittyBufficorns.Farmer storage __farmer = __storage.farmers[_farmerId];
        require(bytes(__farmer.name).length == 0, "WittyBufficornsToken: already minted");
        
        _verifySignatorSignature(
            _tokenOwner,
            _ranchId,
            _farmerId,
            _farmerScore,
            _farmerName,
            _farmerAwards,
            _signature
        );

        // Set farmer's info for the first and only time:
        __farmer.name = _farmerName;
        __farmer.score = _farmerScore;
        __farmer.ranchId = _ranchId;

        WittyBufficornsLib.TokenInfo memory _tokenInfo;

        // Set common parameters to all tokens minted within this call:
        _tokenInfo.farmerId = _farmerId;
        // solhint-disable-next-line not-rely-on-time
        _tokenInfo.expeditionTs = block.timestamp;

        // Loop: Mint one token per received award:
        for (uint _ix = 0; _ix < _farmerAwards.length; _ix ++) {
            _tokenInfo.award = _farmerAwards[_ix];
            __doSafeMint(_tokenOwner, _tokenInfo);
        }

        // Increase total number of farmers that minted at least one award:
        __storage.stats.totalFarmers ++;
    }

    function previewFarmerAwards(
            address _tokenOwner,
            uint256 _ranchId,
            uint256 _farmerId,
            uint256 _farmerScore,
            string calldata _farmerName,
            WittyBufficornsLib.Award[] calldata _farmerAwards,
            bytes calldata _signature
        )
        external view
        virtual override
        inStatus(WittyBufficornsLib.Status.Awarding)
    {
        require(_tokenOwner != address(0), "WittyBufficornsToken: no token owner");
        require(_farmerAwards.length > 0, "WittyBufficornsToken: no awards");

        WittyBufficornsLib.TokenMetadata memory _token;
        _token.ranch = __storage.ranches[_ranchId];
        require(_token.ranch.score > 0, "WittyBufficornsToken: inexistent ranch");
        (_token.ranch.weatherTimestamp, _token.ranch.weatherDescription) = getRanchWeather(_ranchId);
        
        _verifySignatorSignature(
            _tokenOwner,
            _ranchId,
            _farmerId,
            _farmerScore,
            _farmerName,
            _farmerAwards,
            _signature
        );

        _token.farmer.name = _farmerName;
        _token.farmer.score = _farmerScore;
        _token.tokenInfo.farmerId = _farmerId;

        WittyBufficorns.TokenInfo memory _tokenInfo;
        _tokenInfo.farmerId = _farmerId;

        _svgs = new string[](_farmerAwards.length);
        for (uint _ix = 0; _ix < _farmerAwards.length; _ix ++) {
            _tokenInfo.award = _farmerAwards[_ix];
            _svgs[_ix] = IWittyBufficornsDecorator(__storage.decorator).toSVG(
                _tokenInfo,
                _farmer,
                _ranch,
                __storage.bufficorns[
                    uint8(_tokenInfo.award.category) >= uint8(WittyBufficorns.Awards.BestBufficorn)
                        ? _tokenInfo.award.bufficornId
                        : 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                ]
            );
        }
    }


    // ========================================================================
    // --- Implementation of 'IWittyBufficornsView' ---------------------------

    function getBufficorn(uint256 _bufficornId)
        external view
        override
        returns (WittyBufficornsLib.Bufficorn memory)
    {
        return __storage.bufficorns[_bufficornId];
    }

    function getFarmer(uint256 _farmerId)
        external view
        override
        returns (WittyBufficornsLib.Farmer memory)
    {
        return __storage.farmers[_farmerId];
    }

    function getRanch(uint256 _ranchId)
        external view
        override
        returns (WittyBufficornsLib.Ranch memory _ranch)
    {
        _ranch = __storage.ranches[_ranchId];
        (_ranch.weatherTimestamp, _ranch.weatherDescription) = getRanchWeather(_ranchId);
    }

    function getRanchWeather(uint256 _ranchId)
        public view
        override
        returns (
            uint256 _lastTimestamp,
            string memory _lastDescription
        )
    {
        WittyBufficornsLib.Ranch storage __ranch = __storage.ranches[_ranchId];
        uint _lastValidQueryId = __ranch.witnet.lastValidQueryId;
        uint _latestQueryId = __ranch.witnet.latestQueryId;
        Witnet.QueryStatus _latestQueryStatus = witnet.getQueryStatus(_latestQueryId);
        Witnet.Response memory _response;
        Witnet.Result memory _result;
        // First try to read weather from latest request, in case it was succesfully solved:
        if (_latestQueryId > 0 && _latestQueryStatus == Witnet.QueryStatus.Reported) {
            _response = witnet.readResponse(_latestQueryId);
            _result = witnet.resultFromCborBytes(_response.cborBytes);
            if (_result.success) {
                return (
                    _response.timestamp,
                    witnet.asString(_result)
                );
            }
        }
        // If not solved, or solved with errors, read weather from last valid request:
        _response = witnet.readResponse(_lastValidQueryId);
        _result = witnet.resultFromCborBytes(_response.cborBytes);
        _lastTimestamp = _response.timestamp;
        _lastDescription = witnet.asString(_result);
    }

    function getTokenInfo(uint256 _tokenId)
        external view 
        override
        tokenExists(_tokenId)
        returns (WittyBufficornsLib.TokenInfo memory)
    {
        return __storage.awards[_tokenId];
    }

    function stopBreedingBlock()
        external view
        override
        returns (uint256)
    {
        return __storage.stopBreedingBlock;
    }

    function stopBreedingRandomness()
        external view
        override
        returns (bytes32)
    {
        return __storage.stopBreedingRandomness;
    }

    function toJSON(uint256 _tokenId)
        public view
        override
        tokenExists(_tokenId)
        returns (string memory)
    {
        WittyBufficornsLib.TokenMetadata memory _metadata;
        _metadata.tokenInfo = __storage.awards[_tokenId];
        _metadata.farmer = __storage.farmers[_metadata.tokenInfo.farmerId];
        _metadata.ranch = __storage.ranches[_metadata.farmer.ranchId];
        (_metadata.ranch.weatherTimestamp, _metadata.ranch.weatherDescription) = getRanchWeather(_metadata.farmer.ranchId);
        if (
            uint8(_metadata.tokenInfo.award.category) >= uint8(WittyBufficornsLib.Awards.BestBufficorn)
        ) {
            _metadata.bufficorn = __storage.bufficorns[_metadata.tokenInfo.award.bufficornId];
        }
        return IWittyBufficornsDecorator(__storage.decorator).toJSON(
            _token,
            _farmer,
            _ranch,
            _bufficorn
        );
    }

    function toSVG(uint256 _tokenId)
        public view
        override
        tokenExists(_tokenId)
        returns (string memory)
    {
        WittyBufficorns.TokenInfo memory _token = __storage.awards[_tokenId];
        WittyBufficorns.Farmer memory _farmer = __storage.farmers[_token.farmerId];
        WittyBufficorns.Ranch memory _ranch = __storage.ranches[_farmer.ranchId];
        (_ranch.weatherTimestamp, _ranch.weatherDescription) = getRanchWeather(_farmer.ranchId);
        WittyBufficorns.Bufficorn memory _bufficorn;
        if (
            uint8(_token.award.category) >= uint8(WittyBufficorns.Awards.BestBufficorn)
        ) {
            _bufficorn = __storage.bufficorns[_token.award.bufficornId];
        }
        return IWittyBufficornsDecorator(__storage.decorator).toSVG(
            _token,
            _farmer,
            _ranch,
            _bufficorn
        );
    }
    
    function totalBufficorns() public view override returns (uint256) {
        return __storage.stats.totalBufficorns;
    }

    function totalFarmers() public view override returns (uint256) {
        return __storage.stats.totalFarmers;
    }

    function totalRanches() public view override returns (uint256) {
        return __storage.stats.totalRanches;
    }

    function totalSupply() public view override returns (uint256) {
        return __storage.stats.totalSupply;
    }


    // ------------------------------------------------------------------------
    // --- INTERNAL METHODS ---------------------------------------------------
    // ------------------------------------------------------------------------

    function __doSafeMint(
            address _tokenOwner,
            WittyBufficornsLib.TokenInfo memory _tokenInfo
        )
        internal
        returns (uint256 _tokenId)
    {
        _tokenId = ++ __storage.stats.totalSupply;               
        __storage.awards[_tokenId] = _tokenInfo;
        _safeMint(_tokenOwner, _tokenId);
    }

    function _verifySignatorSignature(
            address _tokenOwner,
            uint256 _ranchId,
            uint256 _farmerId,
            uint256 _farmerScore,
            string memory _farmerName,
            WittyBufficornsLib.Award[] memory _farmerAwards,
            bytes memory _signature
        )
        internal view
        virtual
    {
        // Verify signator:
        bytes32 _hash = keccak256(abi.encode(
            _tokenOwner,
            _ranchId,
            _farmerId,
            _farmerScore,
            _farmerName,
            _farmerAwards
        ));
        require(
            WittyBufficorns.recoverAddr(_hash, _signature) == __storage.signator,
            "WittyBufficornsToken: bad signature"
        );
    }
}
