// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ArbSys} from "./ArbSys.sol";
import {ERC20} from "../lib/openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title DegenGambit
/// @notice This is the game contract for Degen's Gambit, a permissionless slot machine game.
/// @notice Degen's Gambit comes with a streak mechanic. Players get an ERC20 GAMBIT token every time
/// they extend their streak. They can spend a GAMBIT token to spin with improved odds of winning.
/// @dev This ocntract depends on the ArbSys precompile that comes on Arbitrum Nitro chains to provide the current block number.
/// For more details: https://docs.arbitrum.io/build-decentralized-apps/arbitrum-vs-ethereum/block-numbers-and-time
contract DegenGambit is ERC20, ReentrancyGuard {
    uint256 private constant BITS_30 = 0x3FFFFFFF;
    uint256 private constant SECONDS_PER_DAY = 60 * 60 * 24;

    /// The GAMBIT reward for daily streaks.
    uint256 public constant DailyStreakReward = 1e18;

    /// The GAMBIT reward for weekly streaks.
    uint256 public constant WeeklyStreakReward = 5e18;

    /// The Gambit Prize for case same minor left, right different minor center
    uint256 public constant MinorGambitPrize = 3e18;

    /// The Gambit Prize for having at least 1 major symbol and nothing else
    uint256 public constant MajorGambitPrize = 1e18;

    // Cumulative mass functions for probability distributions. Total mass for each distribution is 2^30 = 1073741824.
    // These values were generated by the game design notebook. If you know, you know.

    /// Cumulative mass function for the UnmodifiedLeftReel
    uint256[19] public UnmodifiedLeftReel = [
        0 + 24970744, // 0 - 0 (null)
        24970744 + 99882960, // 1 - Gold star (minor)
        124853704 + 49941480, // 2 - Diamonds (suit) (minor)
        174795184 + 49941480, // 3 - Clubs (suit) (minor)
        224736664 + 99882960, // 4 - Spades (suit) (minor)
        324619624 + 49941480, // 5 - Hearts (suit) (minor)
        374561104 + 49941480, // 6 - Diamond (gem) (minor)
        424502584 + 99882960, // 7 - Banana (minor)
        524385544 + 49941480, // 8 - Cherry (minor)
        574327024 + 49941480, // 9 - Pineapple (minor)
        624268504 + 99882960, // 10 - Orange (minor)
        724151464 + 49941480, // 11 - Apple (minor)
        774092944 + 49941480, // 12 - Bell (minor)
        824034424 + 99882960, // 13 - Gold coin (minor)
        923917384 + 49941480, // 14 - Crescent moon (minor)
        973858864 + 49941480, // 15 - Full moon (minor)
        1023800344 + 24970740, // 16 - Gold 7 (major)
        1048771084 + 12485370, // 17 - Red 7 (major)
        1061256454 + 12485370 // 18 - Diamond 7 (major)
    ];

    /// Cumulative mass function for the UnmodifiedCenterReel
    uint256[19] public UnmodifiedCenterReel = [
        0 + 24970744, // 0 - 0 (null)
        24970744 + 49941480, // 1 - Gold star (minor)
        74912224 + 99882960, // 2 - Diamonds (suit) (minor)
        174795184 + 49941480, // 3 - Clubs (suit) (minor)
        224736664 + 49941480, // 4 - Spades (suit) (minor)
        274678144 + 99882960, // 5 - Hearts (suit) (minor)
        374561104 + 49941480, // 6 - Diamond (gem) (minor)
        424502584 + 49941480, // 7 - Banana (minor)
        474444064 + 99882960, // 8 - Cherry (minor)
        574327024 + 49941480, // 9 - Pineapple (minor)
        624268504 + 49941480, // 10 - Orange (minor)
        674209984 + 99882960, // 11 - Apple (minor)
        774092944 + 49941480, // 12 - Bell (minor)
        824034424 + 49941480, // 13 - Gold coin (minor)
        873975904 + 99882960, // 14 - Crescent moon (minor)
        973858864 + 49941480, // 15 - Full moon (minor)
        1023800344 + 12485370, // 16 - Gold 7 (major)
        1036285714 + 24970740, // 17 - Red 7 (major)
        1061256454 + 12485370 // 18 - Diamond 7 (major)
    ];

    /// Cumulative mass function for the UnmodifiedCenterReel
    uint256[19] public UnmodifiedRightReel = [
        0 + 24970744, // 0 - 0 (null)
        24970744 + 49941480, // 1 - Gold star (minor)
        74912224 + 49941480, // 2 - Diamonds (suit) (minor)
        124853704 + 99882960, // 3 - Clubs (suit) (minor)
        224736664 + 49941480, // 4 - Spades (suit) (minor)
        274678144 + 49941480, // 5 - Hearts (suit) (minor)
        324619624 + 99882960, // 6 - Diamond (gem) (minor)
        424502584 + 49941480, // 7 - Banana (minor)
        474444064 + 49941480, // 8 - Cherry (minor)
        524385544 + 99882960, // 9 - Pineapple (minor)
        624268504 + 49941480, // 10 - Orange (minor)
        674209984 + 49941480, // 11 - Apple (minor)
        724151464 + 99882960, // 12 - Bell (minor)
        824034424 + 49941480, // 13 - Gold coin (minor)
        873975904 + 49941480, // 14 - Crescent moon (minor)
        923917384 + 99882960, // 15 - Full moon (minor)
        1023800344 + 12485370, // 16 - Gold 7 (major)
        1036285714 + 12485370, // 17 - Red 7 (major)
        1048771084 + 24970740 // 18 - Diamond 7 (major)
    ];

    /// Cumulative mass function for the ImprovedLeftReel
    uint256[19] public ImprovedLeftReel = [
        0 + 2526414, // 0 - 0 (null)
        2526414 + 102068183, // 1 - Gold star (minor)
        104594597 + 51034067, // 2 - Diamonds (suit) (minor)
        155628664 + 51034067, // 3 - Clubs (suit) (minor)
        206662731 + 102068183, // 4 - Spades (suit) (minor)
        308730914 + 51034067, // 5 - Hearts (suit) (minor)
        359764981 + 51034067, // 6 - Diamond (gem) (minor)
        410799048 + 102068183, // 7 - Banana (minor)
        512867231 + 51034067, // 8 - Cherry (minor)
        563901298 + 51034067, // 9 - Pineapple (minor)
        614935365 + 102068183, // 10 - Orange (minor)
        717003548 + 51034067, // 11 - Apple (minor)
        768037615 + 51034067, // 12 - Bell (minor)
        819071682 + 102068183, // 13 - Gold coin (minor)
        921139865 + 51034067, // 14 - Crescent moon (minor)
        972173932 + 51034067, // 15 - Full moon (minor)
        1023207999 + 25266913, // 16 - Gold 7 (major)
        1048474912 + 12633456, // 17 - Red 7 (major)
        1061108368 + 12633456 // 18 - Diamond 7 (major)
    ];

    /// Cumulative mass function for the ImprovedCenterReel
    uint256[19] public ImprovedCenterReel = [
        0 + 2526414, // 0 - 0 (null)
        2526414 + 51034067, // 1 - Gold star (minor)
        53560481 + 102068183, // 2 - Diamonds (suit) (minor)
        155628664 + 51034067, // 3 - Clubs (suit) (minor)
        206662731 + 51034067, // 4 - Spades (suit) (minor)
        257696798 + 102068183, // 5 - Hearts (suit) (minor)
        359764981 + 51034067, // 6 - Diamond (gem) (minor)
        410799048 + 51034067, // 7 - Banana (minor)
        461833115 + 102068183, // 8 - Cherry (minor)
        563901298 + 51034067, // 9 - Pineapple (minor)
        614935365 + 51034067, // 10 - Orange (minor)
        665969432 + 102068183, // 11 - Apple (minor)
        768037615 + 51034067, // 12 - Bell (minor)
        819071682 + 51034067, // 13 - Gold coin (minor)
        870105749 + 102068183, // 14 - Crescent moon (minor)
        972173932 + 51034067, // 15 - Full moon (minor)
        1023207999 + 12633456, // 16 - Gold 7 (major)
        1035841455 + 25266913, // 17 - Red 7 (major)
        1061108368 + 12633456 // 18 - Diamond 7 (major)
    ];

    /// Cumulative mass function for the ImprovedCenterReel
    uint256[19] public ImprovedRightReel = [
        0 + 2526414, // 0 - 0 (null)
        2526414 + 51034067, // 1 - Gold star (minor)
        53560481 + 51034067, // 2 - Diamonds (suit) (minor)
        104594548 + 102068183, // 3 - Clubs (suit) (minor)
        206662731 + 51034067, // 4 - Spades (suit) (minor)
        257696798 + 51034067, // 5 - Hearts (suit) (minor)
        308730865 + 102068183, // 6 - Diamond (gem) (minor)
        410799048 + 51034067, // 7 - Banana (minor)
        461833115 + 51034067, // 8 - Cherry (minor)
        512867182 + 102068183, // 9 - Pineapple (minor)
        614935365 + 51034067, // 10 - Orange (minor)
        665969432 + 51034067, // 11 - Apple (minor)
        717003499 + 102068183, // 12 - Bell (minor)
        819071682 + 51034067, // 13 - Gold coin (minor)
        870105749 + 51034067, // 14 - Crescent moon (minor)
        921139816 + 102068183, // 15 - Full moon (minor)
        1023207999 + 12633456, // 16 - Gold 7 (major)
        1035841455 + 12633456, // 17 - Red 7 (major)
        1048474911 + 25266913 // 18 - Diamond 7 (major)
    ];

    /// How many blocks a player has to act (respin/accept).
    uint256 public BlocksToAct;

    /// The block number of the last spin/respin by each player.
    mapping(address => uint256) public LastSpinBlock;

    /// Whether or not the last spin for a given player is a boosted spin.
    mapping(address => bool) public LastSpinBoosted;

    /// Cost (finest denomination of native token on the chain) to roll.
    uint256 public CostToSpin;

    /// Cost (finest denomination of native token on the chain) to reroll.
    uint256 public CostToRespin;

    /// Day on which the last in-streak spin was made by a given player. This is for daily streaks.
    mapping(address => uint256) public LastStreakDay;

    /// The length of the current daily streak the made by a given player. This is for daily streak length.
    mapping(address => uint256) public CurrentDailyStreakLength;

    /// Week on which the last in-streak spin was made by a given player. This is for weekly streaks.
    mapping(address => uint256) public LastStreakWeek;

    /// The length of the current weekly streak the made by a given player. This is for weekly streak length.
    mapping(address => uint256) public CurrentWeeklyStreakLength;

    /// Fired when a player spins (and respins).
    event Spin(address indexed player, bool indexed bonus);
    /// Fired when a player accepts the outcome of a roll.
    event Award(address indexed player, uint256 value);
    /// Fired when a player continues a daily streak.
    event DailyStreak(address indexed player, uint256 day);
    /// Fired when a player continues a weekly streak.
    event WeeklyStreak(address indexed player, uint256 week);

    /// Signifies that the player is no longer able to act because too many blocks elapsed since their
    /// last action.
    error DeadlineExceeded();
    /// This error is raised to signify that the player needs to wait for at least one more block to elapse.
    error WaitForTick();
    /// Signifies that the player has not provided enough value to perform the action.
    error InsufficientValue();
    /// Signifies that a reel outcome is out of bounds.
    error OutcomeOutOfBounds();
    // Signifies that Prize transfer has failed
    error FailedPrizeTransfer();

    function supportsInterface(bytes4 interfaceID) public pure returns (bool) {
        return
            interfaceID == 0x01ffc9a7 || // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceID == 0x36372b07; // ERC20 support -- all methods on OpenZeppelin IERC20 excluding "name", "symbol", and "decimals".
    }

    struct Winner {
        address player;
        uint256 amount;
        uint256 timestamp;
    }

    Winner[] public winners;

    /// In addition to the game mechanics, DegensGambit is also an ERC20 contract in which the ERC20
    /// tokens represent bonus spins. The symbol for this contract is GAMBIT.
    constructor(
        uint256 blocksToAct,
        uint256 costToSpin,
        uint256 costToRespin
    ) ERC20("Degen's Gambit", "GAMBIT") {
        BlocksToAct = blocksToAct;
        CostToSpin = costToSpin;
        CostToRespin = costToRespin;
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 0
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 1
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 2
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 3
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 4
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 5
        winners.push(
            Winner({player: address(0), amount: 0, timestamp: block.timestamp})
        ); // 6
    }

    /// Allows the contract to receive the native token on its blockchain.
    receive() external payable {}

    /// Updates the winners array with the latest winner
    function updateWinners(
        address player,
        uint256 amount,
        uint256 prizeIndex
    ) internal {
        winners[prizeIndex] = Winner({
            player: player,
            amount: amount,
            timestamp: block.timestamp
        });
    }

    /// The GAMBIT token (representing bonus rolls on the Degen's Gambit slot machine) has 0 decimals.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function _blockNumber() internal view returns (uint256) {
        return ArbSys(address(100)).arbBlockNumber();
    }

    function _blockhash(uint256 number) internal view returns (bytes32) {
        return ArbSys(address(100)).arbBlockHash(number);
    }

    function _enforceTick(address degenerate) internal view {
        if (_blockNumber() <= LastSpinBlock[degenerate]) {
            revert WaitForTick();
        }
    }

    function _enforceDeadline(address degenerate) internal view {
        if (_blockNumber() > LastSpinBlock[degenerate] + BlocksToAct) {
            revert DeadlineExceeded();
        }
    }

    function _entropy(
        address degenerate
    ) internal view virtual returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encode(
                        _blockhash(LastSpinBlock[degenerate]),
                        degenerate
                    )
                )
            );
    }

    /// sampleUnmodifiedLeftReel samples the outcome from UnmodifiedLeftReel specified by the given entropy
    function sampleUnmodifiedLeftReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = (entropy >> 60) & BITS_30;
        if (sample < UnmodifiedLeftReel[0]) {
            return 0;
        } else if (sample < UnmodifiedLeftReel[1]) {
            return 1;
        } else if (sample < UnmodifiedLeftReel[2]) {
            return 2;
        } else if (sample < UnmodifiedLeftReel[3]) {
            return 3;
        } else if (sample < UnmodifiedLeftReel[4]) {
            return 4;
        } else if (sample < UnmodifiedLeftReel[5]) {
            return 5;
        } else if (sample < UnmodifiedLeftReel[6]) {
            return 6;
        } else if (sample < UnmodifiedLeftReel[7]) {
            return 7;
        } else if (sample < UnmodifiedLeftReel[8]) {
            return 8;
        } else if (sample < UnmodifiedLeftReel[9]) {
            return 9;
        } else if (sample < UnmodifiedLeftReel[10]) {
            return 10;
        } else if (sample < UnmodifiedLeftReel[11]) {
            return 11;
        } else if (sample < UnmodifiedLeftReel[12]) {
            return 12;
        } else if (sample < UnmodifiedLeftReel[13]) {
            return 13;
        } else if (sample < UnmodifiedLeftReel[14]) {
            return 14;
        } else if (sample < UnmodifiedLeftReel[15]) {
            return 15;
        } else if (sample < UnmodifiedLeftReel[16]) {
            return 16;
        } else if (sample < UnmodifiedLeftReel[17]) {
            return 17;
        }
        return 18;
    }

    /// sampleUnmodifiedCenterReel samples the outcome from UnmodifiedCenterReel specified by the given entropy
    function sampleUnmodifiedCenterReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = (entropy >> 30) & BITS_30;
        if (sample < UnmodifiedCenterReel[0]) {
            return 0;
        } else if (sample < UnmodifiedCenterReel[1]) {
            return 1;
        } else if (sample < UnmodifiedCenterReel[2]) {
            return 2;
        } else if (sample < UnmodifiedCenterReel[3]) {
            return 3;
        } else if (sample < UnmodifiedCenterReel[4]) {
            return 4;
        } else if (sample < UnmodifiedCenterReel[5]) {
            return 5;
        } else if (sample < UnmodifiedCenterReel[6]) {
            return 6;
        } else if (sample < UnmodifiedCenterReel[7]) {
            return 7;
        } else if (sample < UnmodifiedCenterReel[8]) {
            return 8;
        } else if (sample < UnmodifiedCenterReel[9]) {
            return 9;
        } else if (sample < UnmodifiedCenterReel[10]) {
            return 10;
        } else if (sample < UnmodifiedCenterReel[11]) {
            return 11;
        } else if (sample < UnmodifiedCenterReel[12]) {
            return 12;
        } else if (sample < UnmodifiedCenterReel[13]) {
            return 13;
        } else if (sample < UnmodifiedCenterReel[14]) {
            return 14;
        } else if (sample < UnmodifiedCenterReel[15]) {
            return 15;
        } else if (sample < UnmodifiedCenterReel[16]) {
            return 16;
        } else if (sample < UnmodifiedCenterReel[17]) {
            return 17;
        }
        return 18;
    }

    /// sampleUnmodifiedRightReel samples the outcome from UnmodifiedRightReel specified by the given entropy
    function sampleUnmodifiedRightReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = entropy & BITS_30;
        if (sample < UnmodifiedRightReel[0]) {
            return 0;
        } else if (sample < UnmodifiedRightReel[1]) {
            return 1;
        } else if (sample < UnmodifiedRightReel[2]) {
            return 2;
        } else if (sample < UnmodifiedRightReel[3]) {
            return 3;
        } else if (sample < UnmodifiedRightReel[4]) {
            return 4;
        } else if (sample < UnmodifiedRightReel[5]) {
            return 5;
        } else if (sample < UnmodifiedRightReel[6]) {
            return 6;
        } else if (sample < UnmodifiedRightReel[7]) {
            return 7;
        } else if (sample < UnmodifiedRightReel[8]) {
            return 8;
        } else if (sample < UnmodifiedRightReel[9]) {
            return 9;
        } else if (sample < UnmodifiedRightReel[10]) {
            return 10;
        } else if (sample < UnmodifiedRightReel[11]) {
            return 11;
        } else if (sample < UnmodifiedRightReel[12]) {
            return 12;
        } else if (sample < UnmodifiedRightReel[13]) {
            return 13;
        } else if (sample < UnmodifiedRightReel[14]) {
            return 14;
        } else if (sample < UnmodifiedRightReel[15]) {
            return 15;
        } else if (sample < UnmodifiedRightReel[16]) {
            return 16;
        } else if (sample < UnmodifiedRightReel[17]) {
            return 17;
        }
        return 18;
    }

    /// sampleImprovedLeftReel samples the outcome from ImprovedLeftReel specified by the given entropy
    function sampleImprovedLeftReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = (entropy >> 60) & BITS_30;
        if (sample < ImprovedLeftReel[0]) {
            return 0;
        } else if (sample < ImprovedLeftReel[1]) {
            return 1;
        } else if (sample < ImprovedLeftReel[2]) {
            return 2;
        } else if (sample < ImprovedLeftReel[3]) {
            return 3;
        } else if (sample < ImprovedLeftReel[4]) {
            return 4;
        } else if (sample < ImprovedLeftReel[5]) {
            return 5;
        } else if (sample < ImprovedLeftReel[6]) {
            return 6;
        } else if (sample < ImprovedLeftReel[7]) {
            return 7;
        } else if (sample < ImprovedLeftReel[8]) {
            return 8;
        } else if (sample < ImprovedLeftReel[9]) {
            return 9;
        } else if (sample < ImprovedLeftReel[10]) {
            return 10;
        } else if (sample < ImprovedLeftReel[11]) {
            return 11;
        } else if (sample < ImprovedLeftReel[12]) {
            return 12;
        } else if (sample < ImprovedLeftReel[13]) {
            return 13;
        } else if (sample < ImprovedLeftReel[14]) {
            return 14;
        } else if (sample < ImprovedLeftReel[15]) {
            return 15;
        } else if (sample < ImprovedLeftReel[16]) {
            return 16;
        } else if (sample < ImprovedLeftReel[17]) {
            return 17;
        }
        return 18;
    }

    /// sampleImprovedCenterReel samples the outcome from ImprovedCenterReel specified by the given entropy
    function sampleImprovedCenterReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = (entropy >> 30) & BITS_30;
        if (sample < ImprovedCenterReel[0]) {
            return 0;
        } else if (sample < ImprovedCenterReel[1]) {
            return 1;
        } else if (sample < ImprovedCenterReel[2]) {
            return 2;
        } else if (sample < ImprovedCenterReel[3]) {
            return 3;
        } else if (sample < ImprovedCenterReel[4]) {
            return 4;
        } else if (sample < ImprovedCenterReel[5]) {
            return 5;
        } else if (sample < ImprovedCenterReel[6]) {
            return 6;
        } else if (sample < ImprovedCenterReel[7]) {
            return 7;
        } else if (sample < ImprovedCenterReel[8]) {
            return 8;
        } else if (sample < ImprovedCenterReel[9]) {
            return 9;
        } else if (sample < ImprovedCenterReel[10]) {
            return 10;
        } else if (sample < ImprovedCenterReel[11]) {
            return 11;
        } else if (sample < ImprovedCenterReel[12]) {
            return 12;
        } else if (sample < ImprovedCenterReel[13]) {
            return 13;
        } else if (sample < ImprovedCenterReel[14]) {
            return 14;
        } else if (sample < ImprovedCenterReel[15]) {
            return 15;
        } else if (sample < ImprovedCenterReel[16]) {
            return 16;
        } else if (sample < ImprovedCenterReel[17]) {
            return 17;
        }
        return 18;
    }

    /// sampleImprovedRightReel samples the outcome from ImprovedRightReel specified by the given entropy
    function sampleImprovedRightReel(
        uint256 entropy
    ) public view returns (uint256) {
        uint256 sample = entropy & BITS_30;
        if (sample < ImprovedRightReel[0]) {
            return 0;
        } else if (sample < ImprovedRightReel[1]) {
            return 1;
        } else if (sample < ImprovedRightReel[2]) {
            return 2;
        } else if (sample < ImprovedRightReel[3]) {
            return 3;
        } else if (sample < ImprovedRightReel[4]) {
            return 4;
        } else if (sample < ImprovedRightReel[5]) {
            return 5;
        } else if (sample < ImprovedRightReel[6]) {
            return 6;
        } else if (sample < ImprovedRightReel[7]) {
            return 7;
        } else if (sample < ImprovedRightReel[8]) {
            return 8;
        } else if (sample < ImprovedRightReel[9]) {
            return 9;
        } else if (sample < ImprovedRightReel[10]) {
            return 10;
        } else if (sample < ImprovedRightReel[11]) {
            return 11;
        } else if (sample < ImprovedRightReel[12]) {
            return 12;
        } else if (sample < ImprovedRightReel[13]) {
            return 13;
        } else if (sample < ImprovedRightReel[14]) {
            return 14;
        } else if (sample < ImprovedRightReel[15]) {
            return 15;
        } else if (sample < ImprovedRightReel[16]) {
            return 16;
        } else if (sample < ImprovedRightReel[17]) {
            return 17;
        }
        return 18;
    }

    /// Returns the final symbols on the left, center, and right reels respectively for a spin with
    /// the given entropy. The unused entropy is also returned for use by game clients.
    /// @param entropy The entropy created by the spin.
    /// @param boosted Whether or not the spin was boosted.
    function outcome(
        uint256 entropy,
        bool boosted
    )
        public
        view
        returns (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy
        )
    {
        if (boosted) {
            left = sampleImprovedLeftReel(entropy);
            center = sampleImprovedCenterReel(entropy);
            right = sampleImprovedRightReel(entropy);
        } else {
            left = sampleUnmodifiedLeftReel(entropy);
            center = sampleUnmodifiedCenterReel(entropy);
            right = sampleUnmodifiedRightReel(entropy);
        }

        remainingEntropy = entropy >> 90;
    }

    /// Payout function for symbol combinations.
    function payout(
        uint256 left,
        uint256 center,
        uint256 right
    )
        public
        view
        virtual
        returns (uint256 result, uint256 typeOfPrize, uint256 prizeIndex)
    {
        if (left >= 19 || center >= 19 || right >= 19) {
            revert OutcomeOutOfBounds();
        }
        //Default 0 for everything else
        result = 0;
        if (left != 0 && right != 0 && center != 0) {
            if (left == right && left != center && left <= 15 && center <= 15) {
                // Minor symbol pair on outside reels with different minor symbol in the center. Case 1
                result = MinorGambitPrize;
                typeOfPrize = 20;
                prizeIndex = 1;
            } else if (left == right && left == center && left <= 15) {
                // 3 of a kind with a minor symbol. Case 2
                result = 50 * CostToSpin;
                if (result > address(this).balance >> 6) {
                    result = address(this).balance >> 6;
                }
                typeOfPrize = 1;
                prizeIndex = 2;
            } else if (left == right && center >= 16 && left <= 15) {
                // Minor symbol pair on outside reels with major symbol in the center. Case 3
                result = 100 * CostToSpin;
                if (result > address(this).balance >> 4) {
                    result = address(this).balance >> 4;
                }
                typeOfPrize = 1;
                prizeIndex = 3;
            } else if (
                left != right &&
                center != left &&
                center != right &&
                left >= 16 &&
                center >= 16 &&
                right >= 16
            ) {
                // Three distinct major symbols. Case 4
                result = address(this).balance >> 3;
                typeOfPrize = 1;
                prizeIndex = 5;
            } else if (
                left == right && left != center && left >= 16 && center >= 16
            ) {
                // Major symbol pair on the outside with a different major symbol in the center. Case 5
                result = address(this).balance >> 3;
                typeOfPrize = 1;
                prizeIndex = 4;
            } else if (left == center && center == right && left >= 16) {
                // 3 of a kind with a major symbol. Jackpot! Case 6
                result = address(this).balance >> 1;
                typeOfPrize = 1;
                prizeIndex = 6;
            } else if (left > 15 || center > 15 || right > 15) {
                // If at least 1 Major symbol is present
                result = MajorGambitPrize;
                typeOfPrize = 20;
                prizeIndex = 0;
            }
        }
    }

    // Payout Estimate function to easily display current payouts estimate at time of function call
    function prizes()
        external
        view
        virtual
        returns (uint256[] memory prizesAmount, uint256[] memory typeOfPrize)
    {
        prizesAmount = new uint256[](7);
        typeOfPrize = new uint256[](7);
        prizesAmount[0] = MajorGambitPrize;
        typeOfPrize[0] = 20;
        prizesAmount[1] = MinorGambitPrize;
        typeOfPrize[1] = 20;
        prizesAmount[2] = 50 * CostToSpin < address(this).balance >> 6
            ? 50 * CostToSpin
            : address(this).balance >> 6;
        typeOfPrize[2] = 1;
        prizesAmount[3] = 100 * CostToSpin < address(this).balance >> 4
            ? 100 * CostToSpin
            : address(this).balance >> 4;
        typeOfPrize[3] = 1;
        prizesAmount[4] = address(this).balance >> 3;
        typeOfPrize[4] = 1;
        prizesAmount[5] = address(this).balance >> 3;
        typeOfPrize[5] = 1;
        prizesAmount[6] = address(this).balance >> 1;
        typeOfPrize[6] = 1;
    }

    //This is the function that handles the payout for the prizes
    function _transferPrize(
        uint256 prize,
        address player,
        uint256 typeOfPrize
    ) internal virtual {
        if (typeOfPrize == 1) {
            (bool success, ) = payable(player).call{value: prize}("");
            if (!success) {
                revert FailedPrizeTransfer();
            }
        } else {
            _mint(player, prize);
        }
    }

    //This is a simple function for middleware contracts or UI to determine if there is a prize to accept for player
    function hasPrize(address player) external view returns (bool toReceive) {
        toReceive =
            _blockNumber() > LastSpinBlock[player] &&
            _blockNumber() <= LastSpinBlock[player] + BlocksToAct;
        if (toReceive) {
            (uint256 left, uint256 center, uint256 right, ) = outcome(
                _entropy(player),
                LastSpinBoosted[player]
            );
            (uint256 prize, , ) = payout(left, center, right);
            toReceive = prize > 0;
        }
        return toReceive;
    }

    /// This is the internal function called to accept the outcome of a spin.
    /// @dev This call can be delegated to a different account.
    /// @param player account claiming a prize.
    function _accept(
        address player
    )
        internal
        returns (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy,
            uint256 prize
        )
    {
        uint256 typeOfPrize;
        _enforceTick(player);
        _enforceDeadline(player);

        (left, center, right, remainingEntropy) = outcome(
            _entropy(player),
            LastSpinBoosted[player]
        );
        {
            uint256 prizeIndex;
            (prize, typeOfPrize, prizeIndex) = payout(left, center, right);
            _transferPrize(prize, player, typeOfPrize);
            updateWinners(player, prize, prizeIndex);
        }
        emit Award(player, prize);
        delete LastSpinBoosted[player];
        delete LastSpinBlock[player];
    }

    /// This is the function a player calls to accept the outcome of a spin.
    /// @dev This call cannot be delegated to a different account.
    function accept()
        external
        virtual
        nonReentrant
        returns (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy,
            uint256 prize
        )
    {
        (left, center, right, remainingEntropy, prize) = _accept(msg.sender);
    }

    /// This is the function a player calls to accept the outcome of a spin.
    /// @dev This call can be delegated to a different account.
    /// @param player account claiming a prize.
    function acceptFor(
        address player
    )
        external
        virtual
        nonReentrant
        returns (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy,
            uint256 prize
        )
    {
        (left, center, right, remainingEntropy, prize) = _accept(player);
    }

    function spinCost(address degenerate) public view returns (uint256) {
        if (_blockNumber() <= LastSpinBlock[degenerate] + BlocksToAct) {
            // This means that all degenerates playing in the first BlocksToAct blocks produced on the blockchain
            // get a discount on their early spins.
            return CostToRespin;
        }
        return CostToSpin;
    }

    //Calculates Gambit for playing streaks
    function _streaks(address streakPlayer) internal virtual {
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (LastStreakDay[streakPlayer] < currentDay - 1) {
            delete CurrentDailyStreakLength[streakPlayer];
        }
        if (LastStreakDay[streakPlayer] + 1 == currentDay) {
            _mint(streakPlayer, DailyStreakReward);
            CurrentDailyStreakLength[streakPlayer] += 1;
            emit DailyStreak(streakPlayer, currentDay);
        }

        LastStreakDay[streakPlayer] = currentDay;

        uint256 currentWeek = currentDay / 7;
        if (LastStreakWeek[streakPlayer] < currentWeek - 1) {
            delete CurrentWeeklyStreakLength[streakPlayer];
        }
        if (LastStreakWeek[streakPlayer] + 1 == currentWeek) {
            _mint(streakPlayer, WeeklyStreakReward);
            CurrentWeeklyStreakLength[streakPlayer] += 1;
            emit WeeklyStreak(streakPlayer, currentWeek);
        }

        LastStreakWeek[streakPlayer] = currentWeek;
    }

    /// Spin the slot machine.
    /// @notice If the player sends more value than they absolutely need to, the contract simply accepts it into the pot.
    /// @dev  This call can be delegated to a different account.
    /// @param boost Whether or not the player is using a boost, msg.sender is paying the boost
    /// @param spinPlayer account spin is for
    /// @param streakPlayer account streak reward is for
    /// @param value value being sent to contract
    function _spin(
        address spinPlayer,
        address streakPlayer,
        bool boost,
        uint256 value
    ) internal virtual {
        uint256 requiredFee = spinCost(spinPlayer);
        if (value < requiredFee) {
            revert InsufficientValue();
        }

        _streaks(streakPlayer);

        if (boost) {
            // Burn an ERC20 token off of this contract from the player's account.
            _burn(msg.sender, 1);
        }

        LastSpinBlock[spinPlayer] = _blockNumber();
        LastSpinBoosted[spinPlayer] = boost;

        emit Spin(spinPlayer, boost);
    }

    /// Spin the slot machine.
    /// @notice If the player sends more value than they absolutely need to, the contract simply accepts it into the pot.
    /// @dev  Assumes msg.sender is player. This call cannot be delegated to a different account.
    /// @param boost Whether or not the player is using a boost, msg.sender is paying the boost
    function spin(bool boost) external payable {
        _spin(msg.sender, msg.sender, boost, msg.value);
    }

    /// Spin the slot machine for the spinPlayer.
    /// @notice If the player sends more value than they absolutely need to, the contract simply accepts it into the pot.
    /// @dev  This call can be delegated to a different account.
    /// @param boost Whether or not the player is using a boost, msg.sender is paying the boost
    /// @param spinPlayer account spin is for
    /// @param streakPlayer account streak reward is for
    function spinFor(
        address spinPlayer,
        address streakPlayer,
        bool boost
    ) external payable {
        _spin(spinPlayer, streakPlayer, boost, msg.value);
    }

    /// inspectEntropy is a view method which allows clients to check the current entropy for a player given only their address.
    /// @dev This is a convenience method so that clients don't have to calculate the entropy given the spin blockhash themselves. It
    /// also enforces that blocks have ticked since the spin as well as the `BlocksToAct` deadline.
    function inspectEntropy(
        address degenerate
    ) external view returns (uint256) {
        _enforceDeadline(degenerate);
        return _entropy(degenerate);
    }

    /// inspectOutcome is a view method which allows clients to check the outcome of a spin for a player given only their address.
    /// @notice This method allows clients to simulate the outcome of a spin in a single RPC call.
    /// @dev The alternative to using this method would be to call `accept` (rather than submitting it as a transaction). This is simply a more
    /// convenient and natural way to simulate the outcome of a spin, which also works on-chain.
    function inspectOutcome(
        address degenerate
    )
        external
        view
        returns (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy,
            uint256 prize,
            uint256 typeOfPrize
        )
    {
        _enforceDeadline(degenerate);
        (left, center, right, remainingEntropy) = outcome(
            _entropy(degenerate),
            LastSpinBoosted[degenerate]
        );

        (prize, typeOfPrize, ) = payout(left, center, right);
    }

    function symbol() public view override returns (string memory) {
        bytes32 hash = keccak256(abi.encodePacked(address(this)));
        // Convert to uint256 and take modulus 10^4
        return
            string(
                abi.encodePacked("DG-", Strings.toString(uint256(hash) % 10000))
            );
    }

    /// version pure function that returns a string with version
    function version() external pure virtual returns (string memory) {
        return "1";
    }

    function latestWinners()
        external
        view
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        address[] memory players = new address[](winners.length);
        uint256[] memory amounts = new uint256[](winners.length);
        uint256[] memory timestamps = new uint256[](winners.length);
        for (uint256 i = 0; i < winners.length; i++) {
            players[i] = winners[i].player;
            amounts[i] = winners[i].amount;
            timestamps[i] = winners[i].timestamp;
        }
        return (players, amounts, timestamps);
    }
}
