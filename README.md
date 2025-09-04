# Bitcoin Tax Holding Wallet with Lock Timer 
A secure smart contract wallet that helps manage tax contributions by automatically locking funds until a specified future date. Perfect for businesses and individuals who want to ensure tax payments are properly reserved.

## 🎯 Features

- 💰 Deposit STX tokens with a time lock
- 🔒 Automatic locking mechanism until specified block height
- ⏰ Time-based withdrawal restrictions
- 📊 Configurable tax rate
- 🔍 Balance and unlock time queries
- 🆘 Emergency withdrawal function for contract owner

## 📝 Usage

### Deposit Funds
```clarity
(contract-call? .bitcoin-tax-holding-wallet deposit <amount> <unlock-height>)
```

### Check Balance
```clarity
(contract-call? .bitcoin-tax-holding-wallet get-balance tx-sender)
```

### Withdraw Funds
```clarity
(contract-call? .bitcoin-tax-holding-wallet withdraw <amount>)
```

### Query Tax Rate
```clarity
(contract-call? .bitcoin-tax-holding-wallet get-tax-rate)
```

## ⚠️ Important Notes

- Funds can only be withdrawn after reaching the specified unlock height
- Contract owner can adjust tax rates
- Emergency withdrawal available only to contract owner
- All amounts are in STX tokens

## 🔧 Technical Requirements

- Clarinet
- Stacks blockchain
```
