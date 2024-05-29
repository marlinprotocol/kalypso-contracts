Contracts for interacting with Kalypso

## Note
One of the npm package seems to have issue, hence always use 
`npm install --include-dev --save-exact` 
install all relevant node_modules

### ProofMarketplace

### Generator Registry

# Others
To generate the typings, use `npm run compile` and copy the required files from `./typechain-types`

# Test
To test the contracts, copy environment variables. Replace the default values
`cp env.example .env`

Test
`yarn test`
