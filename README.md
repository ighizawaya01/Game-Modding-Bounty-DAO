# 🎮 Game Modding Bounty DAO

> **Empowering mod creators through decentralized bounty rewards!** 🚀

A Clarity smart contract that creates a decentralized autonomous organization (DAO) for incentivizing and rewarding game mod creators. Community members can pool funds, create bounties, and vote to distribute rewards fairly to the most innovative and useful mods.

## 🌟 Features

- **🏛️ DAO Membership**: Join the community and build your reputation
- **💰 Treasury Management**: Contribute STX to fund bounties
- **🎯 Bounty Creation**: Set up reward pools for specific modding challenges
- **📤 Mod Submissions**: Submit your mods with URLs and descriptions
- **🗳️ Community Voting**: Democratic voting system for mod evaluation
- **🏆 Reward Distribution**: Automatic payouts to winning modders
- **📊 Reputation System**: Track contributions and build credibility

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- STX tokens for testing
- Basic understanding of Clarity smart contracts

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run `clarinet check` to verify the contract

## 📖 Usage Guide

### 1. 🎪 Join the DAO

```clarity
(contract-call? .Game-Modding-Bounty-DAO join-dao)
```

Becomes a DAO member and starts tracking your reputation.

### 2. 💵 Contribute to Treasury

```clarity
(contract-call? .Game-Modding-Bounty-DAO contribute-to-treasury u1000000) ;; 1 STX minimum
```

Add funds to the DAO treasury to enable bounty creation.

### 3. 🎯 Create a Bounty

```clarity
(contract-call? .Game-Modding-Bounty-DAO create-bounty 
  "Epic Weapon Mod" 
  "Create a unique weapon mod for RPG games with special effects"
  u5000000) ;; 5 STX reward
```

Set up a bounty with title, description, and reward amount.

### 4. 📥 Submit Your Mod

```clarity
(contract-call? .Game-Modding-Bounty-DAO submit-mod
  u1 ;; bounty-id
  "https://github.com/user/awesome-weapon-mod"
  "Lightning sword with particle effects and sound")
```

Submit your mod with a URL and description.

### 5. 🗳️ Vote for Submissions

```clarity
(contract-call? .Game-Modding-Bounty-DAO vote-for-submission
  u1 ;; bounty-id
  'SP1EXAMPLE...) ;; submitter address
```

Vote for the best mod submissions during the voting period.

### 6. 🏆 Finalize Bounty

```clarity
(contract-call? .Game-Modding-Bounty-DAO finalize-bounty
  u1 ;; bounty-id
  'SP1WINNER...) ;; winner address
```

Complete the bounty and distribute rewards to the winner (requires minimum votes).

## 📊 Read-Only Functions

### Get Bounty Information
```clarity
(contract-call? .Game-Modding-Bounty-DAO get-bounty u1)
```

### Check Member Details
```clarity
(contract-call? .Game-Modding-Bounty-DAO get-member-info 'SP1EXAMPLE...)
```

### View DAO Statistics
```clarity
(contract-call? .Game-Modding-Bounty-DAO get-dao-stats)
```

### Check Submission Details
```clarity
(contract-call? .Game-Modding-Bounty-DAO get-submission u1 'SP1EXAMPLE...)
```

## ⚙️ Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MIN_BOUNTY_AMOUNT` | 1,000,000 μSTX (1 STX) | Minimum bounty reward |
| `VOTING_PERIOD` | 1,008 blocks (~1 week) | Duration for voting |
| `MIN_VOTES_REQUIRED` | 3 | Minimum votes to finalize |
| `MIN_CONTRIBUTION` | 100,000 μSTX (0.1 STX) | Minimum treasury contribution |

## 🏗️ Contract Architecture

### Data Structures

- **Bounties**: Store bounty details, deadlines, and status
- **Member Registry**: Track member reputation and statistics
- **Submissions**: Link mods to bounties with voting data
- **Votes**: Prevent double voting and track participation
- **Treasury**: Monitor contributions and total funds

### Key Functions

1. **Member Management**: Registration and reputation tracking
2. **Treasury Operations**: Fund collection and allocation
3. **Bounty Lifecycle**: Creation, submission, voting, and completion
4. **Governance**: Democratic voting and reward distribution

## 🛡️ Security Features

- ✅ **Authorization Checks**: Only members can participate
- ✅ **Double Voting Prevention**: One vote per member per submission
- ✅ **Deadline Enforcement**: Time-bound voting periods
- ✅ **Fund Protection**: Treasury balance validation
- ✅ **Status Validation**: Proper bounty state management

## 🚨 Error Codes

| Code | Description |
|------|-------------|
| `u400` | Invalid amount |
| `u401` | Not authorized |
| `u402` | Insufficient funds |
| `u403` | Already voted |
| `u404` | Bounty not found |
| `u405` | Not a DAO member |
| `u410` | Bounty expired |
| `u411` | Bounty not active |

## 🧪 Testing

Run the test suite:
```bash
npm install
npm test
```

Validate the contract:
```bash
clarinet check
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🌐 Community

- **Discord**: Join our modding community discussions
- **GitHub**: Submit issues and feature requests
- **Documentation**: Read the full technical documentation

---

**Built with ❤️ for the modding community**

*Empowering creators, one mod at a time! 🎮✨*

# Game Modding Bounty DAO

