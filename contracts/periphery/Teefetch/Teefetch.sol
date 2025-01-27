// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../risc0/interfaces/RiscZeroVerifierEmergencyStop.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Teefetch {
    RiscZeroVerifierEmergencyStop public immutable VERIFIER;
    bytes32 public immutable IMAGE_ID;

    bytes public pcrs;
    bytes public rootKey;

    mapping(address => bool) public signers;

    event Enrolled(address signer);

    constructor(
        RiscZeroVerifierEmergencyStop _verifier,
        bytes32 _imageId,
        bytes memory _pcrs,
        bytes memory _rootKey
    ) {
        VERIFIER = _verifier;
        IMAGE_ID = _imageId;
        pcrs = _pcrs;
        rootKey = _rootKey;
    }

    function enroll(
        bytes calldata _signerPubkey,
        bytes calldata _seal,
        uint64 _timestampInMilliseconds
    ) external {
        require(
            _timestampInMilliseconds > block.timestamp * 1000 - 3600000,
            "too old"
        );

        (bytes memory pcr0, bytes memory pcr1, bytes memory pcr2) = abi.decode(pcrs, (bytes, bytes, bytes));

        bytes32 _journalDigest = sha256(
            abi.encodePacked(
                _timestampInMilliseconds,
                pcr0,
                pcr1,
                pcr2,
                rootKey,
                _signerPubkey,
                uint16(0)
            )
        );

        VERIFIER.verify(_seal, IMAGE_ID, _journalDigest);

        address _signer = address(uint160(uint256(keccak256(_signerPubkey))));

        signers[_signer] = true;

        emit Enrolled(_signer);
    }

    struct RequestData {
        string url;
        string method;
        string[] headerKeys;
        string[] headerValues;
        string body;
        string[] responseHeaders;
    }

    struct ResponseData {
        uint8 handler;
        uint16 status;
        string[] headerKeys;
        string[] headerValues;
        string body;
        uint64 timestamp;
    }

    struct RequestResponseData {
        RequestData requestData;
        ResponseData responseData;
    }

    bytes32 public constant DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version)"),
                keccak256("marlin.oyster.Teefetch"),
                keccak256("1")
            )
        );

    bytes32 public constant REQUESTRESPONSEDATA_TYPEHASH =
        keccak256(
            "RequestResponseData(RequestData requestData,ResponseData responseData)"
            "RequestData(string url,string method,string[] headerKeys,string[] headerValues,string body,string[] responseHeaders)"
            "ResponseData(uint8 handler,uint16 status,string[] headerKeys,string[] headerValues,string body,uint64 timestamp)"
        );

    bytes32 public constant REQUESTDATA_TYPEHASH =
        keccak256(
            "RequestData(string url,string method,string[] headerKeys,string[] headerValues,string body,string[] responseHeaders)"
        );

    bytes32 public constant RESPONSEDATA_TYPEHASH =
        keccak256(
            "ResponseData(uint8 handler,uint16 status,string[] headerKeys,string[] headerValues,string body,uint64 timestamp)"
        );

    function _requestDataHashStruct(
        RequestData calldata _data
    ) internal pure returns (bytes32) {
        bytes memory _headerAggregator = new bytes(
            _data.headerKeys.length * 32
        );

        for (uint256 i = 0; i < _data.headerKeys.length; i++) {
            bytes32 _hash = keccak256(bytes(_data.headerKeys[i]));
            assembly {
                mstore(add(add(_headerAggregator, 32), mul(i, 32)), _hash)
            }
        }
        bytes32 _headerKeysHash = keccak256(_headerAggregator);

        for (uint256 i = 0; i < _data.headerValues.length; i++) {
            bytes32 _hash = keccak256(bytes(_data.headerValues[i]));
            assembly {
                mstore(add(add(_headerAggregator, 32), mul(i, 32)), _hash)
            }
        }
        bytes32 _headerValuesHash = keccak256(_headerAggregator);

        bytes memory _respHeaderAggregator = new bytes(
            _data.responseHeaders.length * 32
        );

        for (uint256 i = 0; i < _data.responseHeaders.length; i++) {
            bytes32 _hash = keccak256(bytes(_data.responseHeaders[i]));
            assembly {
                mstore(add(add(_respHeaderAggregator, 32), mul(i, 32)), _hash)
            }
        }
        bytes32 _respHeaderHash = keccak256(_respHeaderAggregator);

        return
            keccak256(
                abi.encode(
                    REQUESTDATA_TYPEHASH,
                    keccak256(bytes(_data.url)),
                    keccak256(bytes(_data.method)),
                    _headerKeysHash,
                    _headerValuesHash,
                    keccak256(bytes(_data.body)),
                    _respHeaderHash
                )
            );
    }

    function _responseDataHashStruct(
        ResponseData calldata _data
    ) internal pure returns (bytes32) {
        bytes memory _headerAggregator = new bytes(
            _data.headerKeys.length * 32
        );

        for (uint256 i = 0; i < _data.headerKeys.length; i++) {
            bytes32 _hash = keccak256(bytes(_data.headerKeys[i]));
            assembly {
                mstore(add(add(_headerAggregator, 32), mul(i, 32)), _hash)
            }
        }
        bytes32 _headerKeysHash = keccak256(_headerAggregator);

        for (uint256 i = 0; i < _data.headerValues.length; i++) {
            bytes32 _hash = keccak256(bytes(_data.headerValues[i]));
            assembly {
                mstore(add(add(_headerAggregator, 32), mul(i, 32)), _hash)
            }
        }
        bytes32 _headerValuesHash = keccak256(_headerAggregator);

        return
            keccak256(
                abi.encode(
                    RESPONSEDATA_TYPEHASH,
                    _data.handler,
                    _data.status,
                    _headerKeysHash,
                    _headerValuesHash,
                    keccak256(bytes(_data.body)),
                    _data.timestamp
                )
            );
    }

    function verify(
        RequestResponseData calldata _data,
        bytes calldata _signature
    ) external view {
        bytes32 _hashStruct = keccak256(
            abi.encode(
                REQUESTRESPONSEDATA_TYPEHASH,
                _requestDataHashStruct(_data.requestData),
                _responseDataHashStruct(_data.responseData)
            )
        );
        bytes32 _digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashStruct)
        );

        address _signer = ECDSA.recover(_digest, _signature);

        require(signers[_signer], "unrecognized signer");
    }
}