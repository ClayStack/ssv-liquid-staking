# SSV Liquid Staking Framework

The SSV Liquid Staking Framework serves as the foundation for building a comprehensive liquid staking protocol for Ethereum, leveraging SSV. ClayStack introduces csETH, which incorporates elements of this framework.

## About ClayStack

ClayStack is a pioneering liquid staking protocol designed for the Ethereum ecosystem. Our mission is to lead a new era in the global staking industry, with the aim of bringing staking into the mainstream. Our unique approach, anchored in our commitment to decentralization, security, scalability, and inclusivity, sets us apart. csETH, a key part of our platform, enhances the security of Ethereum and DeFi by fostering active participation and promoting scalable, robust staking.

More at https://www.claystack.com

## What it does?

The SSV Liquid Staking Framework consists of a set of smart contracts that enable users to deposit Ether into a contract and receive an ERC20 token called iETH in return. The contract then stakes the Ether in the consensus layer, and the user's iETH represents their stake in the contract. Users can withdraw their Ether at any time by burning their ssvLiquidToken.

### How to run tests

Make sure you have Foundry installed with all the dependencies.

```
yarn test
```

### Deposits 

- Users can deposit Ether into the contract in exchange for iETH tokens.
- Pending ETH will be automatically staked once the minimum amount is reached.

### Withdraws & Claims

- Users can withdraw their Ether by burning their iETH tokens.
- The contract will burn iETH and start the unbonding process.
- The order can be claimed once contract can cover the amount.
- Deposits from other users that have not been staked yet can help expedite the claim process.

### Validator Registration

The Liquid Token administrator must pre-register valid and active validators. These validators must subsequently be registered in the SSV contract, assuming they are ready to be used for staking.

### Validator Exit

The administrator is responsible for actively managing the registration and balances across the SSV nodes. When the `pendingWithdrawals` in the contract exceeds a certain threshold, the administrator triggers the exit process on a given validator and initiates the unbonding process. The contract receives the withdrawal amount, enabling the user to claim it.

### Oracle

The administrator is expected to oversee a trusted oracle system that updates the contract with balances, active accounts, and exit counts of all validators across the SSV network.



### Caveats

- The framework does not protect iETH holders from slashing. Anyone monitoring the validators could manipulate the market, such as exiting early when slashing occurs before the penalties are reflected in the exchange rate.

- The framework allows anyone to claim a withdrawal as long as there are sufficient funds available. This creates an opportunity for other users to front-run and claim newer orders before older ones, potentially resulting in extended waiting periods until an order can be claimed, exceeding the standard unbonding time.