# Multichain Router Contract
1. install aptos cli
2. aptos move test --package-dir router 
3. aptos move compile --save-metadata --package-dir router
4. aptos move publish --package-dir router --max-gas 500000
   aptos move publish --package-dir anycoin --url https://testnet.aptoslabs.com/
   