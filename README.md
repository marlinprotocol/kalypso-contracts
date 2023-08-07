Contracts for interacting with Kalypso

## ProofMarketPlace

Primary contract for create request (ASK)

## Generator Registry

generators can register and de-register themselves here

## Verifier Wrapper

Every zk scheme is expected to have a wrapper contract that convert the inputs and proofs to simple bytes.

# Others

To generate the typings, use `yarn compile` and copy the required files from `./typechain-types`

# Test

To test the contracts, copy environment variables. Replace the default values
`cp env.example .env`

Test
`yarn test`
