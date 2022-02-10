pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0
import "@openzeppelin/contracts@4.4.1/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts@4.4.1/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.4.1/utils/Strings.sol";
import "../interfaces/IThemisEarlyFarmingNFTDescriptor.sol";
import "../interfaces/IThemisEarlyFarmingNFT.sol";
import "../governance/Governance.sol";
import 'base64-sol/base64.sol';

interface IERC20MetaData {
    function symbol() external view returns (string memory);
}

contract ThemisEarlyFarmingNFTDescriptor is IThemisEarlyFarmingNFTDescriptor,Governance,Initializable {
    using SafeMath for uint256;
    using Strings for uint256;

    string[] public fills = [
                      '', 
                      'fill:#190926;', 
                      'fill:#093C44;', 
                      'fill:#3D1606;',
                      'fill:#150309;',
                      'fill:#00533F;',
                      'fill:#043252;',
                      'fill:#482080;'
                     ];
    string[][] public radialGradients0 = [
                      ['stop-color:#9ED2FF;', 'stop-color:#9ED2FF;stop-opacity:0'],
                      ['stop-color:#FF8500;','stop-color:#F21961;stop-opacity:0;'],
                      ['stop-color:#27B2C4;', 'stop-color:#01497A;stop-opacity:0;'],
                      ['stop-color:#E72758;', 'stop-color:#E6207A;stop-opacity:0;'],
                      ['stop-color:#DF7A10;', 'stop-color:#7A341E;stop-opacity:0;'],
                      ['stop-color:#E72642;','stop-color:#E7334C;stop-opacity:0;'],
                      ['stop-color:#1BA13A;','stop-color:#006758;stop-opacity:0;'],
                      ['stop-color:#DA1528;', 'stop-color:#A01F24;stop-opacity:0;']
                     ];
    string[][] public radialGradients1 = [
                      ['stop-color:#0031B0', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#9D33E2', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#00513A', 'stop-color:#7AD305;stop-opacity:0;'],
                      ['stop-color:#52AF00', 'stop-color:#66132B;stop-opacity:0;'],
                      ['stop-color:#B31A41', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#2E1939','stop-color:#B01585;stop-opacity:0;'],
                      ['stop-color:#782057','stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#124198', 'stop-color:#322965;stop-opacity:0;']
                     ];

    string public namePostfix;   
    IThemisEarlyFarmingNFT public themisEarlyFarmingNFT;            

    function doInitialize(IThemisEarlyFarmingNFT _themisEarlyFarmingNFT) external initializer{
        require(address(_themisEarlyFarmingNFT) != address(0), "ThemisEarlyFarmingNFT address error");
        _governance = msg.sender;
        themisEarlyFarmingNFT = _themisEarlyFarmingNFT;
        namePostfix = '-Vault Quarter';  
        fills = [
                      '', 
                      'fill:#190926;', 
                      'fill:#093C44;', 
                      'fill:#3D1606;',
                      'fill:#150309;',
                      'fill:#00533F;',
                      'fill:#043252;',
                      'fill:#482080;'
                     ];
        radialGradients0 = [
                      ['stop-color:#9ED2FF;', 'stop-color:#9ED2FF;stop-opacity:0'],
                      ['stop-color:#FF8500;','stop-color:#F21961;stop-opacity:0;'],
                      ['stop-color:#27B2C4;', 'stop-color:#01497A;stop-opacity:0;'],
                      ['stop-color:#E72758;', 'stop-color:#E6207A;stop-opacity:0;'],
                      ['stop-color:#DF7A10;', 'stop-color:#7A341E;stop-opacity:0;'],
                      ['stop-color:#E72642;','stop-color:#E7334C;stop-opacity:0;'],
                      ['stop-color:#1BA13A;','stop-color:#006758;stop-opacity:0;'],
                      ['stop-color:#DA1528;', 'stop-color:#A01F24;stop-opacity:0;']
                     ];
        radialGradients1 = [
                      ['stop-color:#0031B0', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#9D33E2', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#00513A', 'stop-color:#7AD305;stop-opacity:0;'],
                      ['stop-color:#52AF00', 'stop-color:#66132B;stop-opacity:0;'],
                      ['stop-color:#B31A41', 'stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#2E1939','stop-color:#B01585;stop-opacity:0;'],
                      ['stop-color:#782057','stop-color:#4700DE;stop-opacity:0;'],
                      ['stop-color:#124198', 'stop-color:#322965;stop-opacity:0;']
                     ];

        
    }

    function generateSvg(uint256 _tokenId,
                         bool _idValid,  
                         address _owner, 
                         string memory _symbol) public view returns(string memory svg) {
        string memory name = string(
            abi.encodePacked(
                _symbol,
                namePostfix
            )
        );                 
        uint256 clrIndex = _calcColor(_tokenId, _idValid);                     
        svg = string(
            abi.encodePacked(
                '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" viewBox="0 0 350 350" style="enable-background:new 0 0 350 350;" xml:space="preserve">',
                _generateCircle(clrIndex),
                _generateSVGID1(clrIndex),
                '<circle style="fill:url(#SVGID_1_);" cx="175.1" cy="175.3" r="175"/>',
                _generateSVGID2(clrIndex),
                _generateBody(),
                _generateTail(_tokenId, name, _owner, _symbol)
            )
        );                           

    }

    function _generateTail(uint256 _tokenId,
                           string memory _name,
                           address _owner,
                           string memory _symbol) internal pure returns(string memory r) {
        r = string(
            abi.encodePacked(
                _generateNameTransform(_name),
                '<text transform="matrix(1 0 0 1 128.0893 248.2279)" style="opacity:0.6;fill:#FFFFFF;enable-background:new;font-size:24px;">ID:',
                _tokenId.toString(),
                '</text>',
                '<path id="SVGID_x5F_3_x5F__4_" style="fill:none;" d="M18.4,175.6c0-86.3,70-156.3,156.3-156.3c86.3,0,156.3,70,156.3,156.3s-70,156.3-156.3,156.3C88.4,331.9,18.4,262,18.4,175.6z"/>',
                '<text><textPath xlink:href="#SVGID_x5F_3_x5F__4_"><tspan style="font-size:16px;fill:#FFFFFF;">',
                addressToString(_owner),
                unicode' • ',
                _symbol,
                '</tspan></textPath><animateTransform attributeName="transform" begin="0s" dur="20s" type="rotate" from="0 175 175" to="360 175 175" repeatCount="indefinite"/></text><text transform="matrix(1 0 0 1 3.051758e-04 0)" style="font-size:12px;"> </text></svg>'
            )
        );                            
    }

    function _generateBody() internal pure returns(string memory r) {
        r = '<circle style="fill:url(#SVGID_2_);" cx="174.4" cy="175.6" r="175"/><g style="opacity:0.8;"><path style="fill:#FFFFFF;fill-opacity:0.8;" d="M189,105.3c-11.1,20.7-21.9,40.7-32.8,60.8c6.9,1.1,6.9,1.1,9.5-3.7c7.1-13.1,14.1-26.2,21.1-39.3c0.5-1.1,1.3-2,2.2-3.3c0.8,1.3,1.3,2.1,1.8,2.9c7.3,13.4,14.5,26.8,21.7,40.3c2.2,4.2,3.3,4.6,9.1,2.9C210.9,145.9,200.1,126,189,105.3z M159.8,119.4c3.3,6.1,6.1,11.4,9.6,17.7c1.2-3.5,3.5-6.5,2.7-8.4c-3.4-7.7-7.9-15.1-12.3-23.4c-11.2,20.9-21.9,40.8-32.8,60.8c6.8,1.2,6.9,1.2,9.5-3.7c6.9-12.7,13.6-25.3,20.5-38C157.9,123,158.6,121.5,159.8,119.4zM178.7,154.7c1.8,2.5,3.1,5.4,4.5,8.1c2.4,4.4,3.5,4.8,9.2,3.1c-4.1-7.6-8.2-15.2-12.5-23.1C176.2,146.7,175.6,150.4,178.7,154.7z"/></g><path style="fill:none;stroke:#FFFFFF;stroke-width:1.0913;stroke-opacity:0.33;" d="M21.4,175.6c0-84.5,68.5-153,153-153c84.5,0,152.9,68.5,152.9,153c0,84.5-68.5,153-152.9,153C89.9,328.6,21.4,260.1,21.4,175.6z"/>';
    }

    function _generateCircle(uint256 _clrIndex) internal view returns (string memory r) {
        r = string(
            abi.encodePacked(
                '<circle style="',
                fills[_clrIndex],
                '" fill="',
                fills[_clrIndex],
                '" cx="175.1" cy="175.3" r="175"/>'
            )
        );
    }

    function _generateSVGID1(uint256 _clrIndex) internal view returns (string memory r) {
        r = string(
            abi.encodePacked(
                '<radialGradient id="SVGID_1_" cx="-1287.2363" cy="153.3023" r="1" gradientTransform="matrix(213.9949 258.784 -180.0549 148.8919 303220.9688 310153.8438)" gradientUnits="userSpaceOnUse">',
                '<stop  offset="0"',
                ' style="',
                radialGradients0[_clrIndex][0],
                '"/>',
                '<stop  offset="1"',
                ' style="',
                radialGradients0[_clrIndex][1],
                '"/></radialGradient>'
            )
        );
    }

    function _generateSVGID2(uint256 _clrIndex) internal view returns (string memory r) {
        r = string(
            abi.encodePacked(
                '<radialGradient id="SVGID_2_" cx="-1288.7415" cy="160.5041" r="1" gradientTransform="matrix(119.3614 -137.8378 226.6339 196.2548 117486.2812 -208858)" gradientUnits="userSpaceOnUse">',
                '<stop  offset="0"',
                ' style="',
                radialGradients1[_clrIndex][0],
                '"/>',
                '<stop  offset="1"',
                ' style="',
                radialGradients1[_clrIndex][1],
                '"/></radialGradient>'
            )
        );
    }

    function _generateNameTransform(string memory _name) internal pure returns (string memory r) {
        r = string(
            abi.encodePacked(
                '<text transform="matrix(1 0 0 1 ',
                _nameTransform(_name).toString(),
                ' 204.6748)',
                '" class="truncate" style="fill:#FFFFFF;font-size:24px; max-width: 100px;">',
                _name,
                '</text>'
            )
        );
    }

    function addressToString(address _address) public pure returns(string memory) {
        bytes32 _bytes = bytes32(uint256(uint160(_address)));
        bytes memory HEX = "0123456789abcdef";
        bytes memory _string = new bytes(42);
        _string[0] = '0';
        _string[1] = 'x';
        for(uint i = 0; i < 20; i++) {
            _string[2+i*2] = HEX[uint8(_bytes[i + 12] >> 4)];
            _string[3+i*2] = HEX[uint8(_bytes[i + 12] & 0x0f)];
        }
        return string(_string);
    }

    function _calcColor(uint256 _tokenId, bool _idValid) internal view returns(uint256) {
        if(!_idValid) {
            return 0;
        }
        return _tokenId.mod(fills.length);
    }

    function _nameTransform(string memory _name) internal pure returns(uint256){
        uint256 length = bytes(_name).length;
        uint256 base = 102;
        uint256 res = _abs(11, length).mul(75);
        uint256 calc = res.div(10);
        return base.sub(calc).add(1);
    }

    function _abs(uint256 a, uint256 b) internal pure returns(uint256) {
        return a > b ? a.sub(b) : b.sub(a);
    }

    function tokenURI(uint256 tokenId) public override(IThemisEarlyFarmingNFTDescriptor) view returns (string memory) {
        IThemisEarlyFarmingNFTStorage.EarlyFarmingNftInfo memory nftInfo = themisEarlyFarmingNFT.earlyFarmingNftInfos(tokenId);
        require(nftInfo.ownerUser != address(0), "Nft Info error");
        string memory symbol = IERC20MetaData(nftInfo.pledgeToken).symbol();
        string memory svg = generateSvg(tokenId, true, nftInfo.ownerUser, symbol);
        return Base64.encode(bytes(svg));
    }
}