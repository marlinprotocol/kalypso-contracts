Contracts for interacting with Kalypso

## Note

One of the npm package seems to have issue, hence always use
`npm install --include-dev --save-exact`
to install all relevant node_modules

### To generate `typescript typings`, use `npm run compile` and copy the required files from `./typechain-types`

### To generate `Rust bindings`, use `forge bind` and copy the required files from `./out/bindings`

### Test
To test the contracts, copy environment variables. Replace the default values
> cp env.example .env

> yarn test
or 
> npm run test

# Note: Don't deploy any contract unless all tests have passed
