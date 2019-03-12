const HDWalletProvider = require('truffle-hdwallet-provider')
const NonceTrackerSubprovider = require('web3-provider-engine/subproviders/nonce-tracker')

const rpcHost = process.env.KEEPER_RPC_HOST
const rpcPort = process.env.KEEPER_RPC_PORT
const url = process.env.KEEPER_RPC_URL

const walletIndex = 0
const walletAccounts = 5

let wallet

const setupWallet = (
    nmemoric,
    url,
    useNonceTracker
) => {
    if (!wallet) {
        wallet = new HDWalletProvider(
            nmemoric,
            url,
            walletIndex,
            walletAccounts)
        if (useNonceTracker) {
            /*
             * This is only required if you connect to infura or nile nodes
             * For details see:
             * https://ethereum.stackexchange.com/questions/44349/truffle-infura-on-mainnet-nonce-too-low-error/50038#50038
             */
            wallet.engine.addProvider(new NonceTrackerSubprovider())
        }
    }
    return wallet
}

module.exports = {
    networks: {
        // only used locally, i.e. ganache
        development: {
            host: rpcHost || 'localhost',
            port: rpcPort || 8545,
            // has to be '*' because this is usually ganache
            network_id: '*',
            gas: 6000000
        },
        // local network for generate coverage
        coverage: {
            host: 'localhost',
            // has to be '*' because this is usually ganache
            network_id: '*',
            port: 8555,
            gas: 0xfffffffffff,
            gasPrice: 0x01
        },
        // spree from docker
        spree: {
            provider: () => setupWallet(
                process.env.NMEMORIC,
                url || `http://localhost:8545`,
                false
            ),
            network_id: 0x2324, // 8996
            gas: 60000000,
            gasPrice: 10000,
            from: '0xe2DD09d719Da89e5a3D0F2549c7E24566e947260'
        },
        // nile the ocean testnet
        nile: {
            provider: () => setupWallet(
                process.env.NMEMORIC,
                url || `https://nile.dev-ocean.com`,
                true
            ),
            network_id: 0x2323, // 8995
            gas: 6000000,
            gasPrice: 10000,
            from: '0x90eE7A30339D05E07d9c6e65747132933ff6e624'
        },
        // kovan testnet
        kovan: {
            provider: () => setupWallet(
                process.env.NMEMORIC,
                url || `https://kovan.infura.io/v2/${process.env.INFURA_TOKEN}`,
                true
            ),
            network_id: 0x2A, // 42
            from: '0x2c0D5F47374b130EE398F4C34DBE8168824A8616'
        }
    },
    compilers: {
        solc: {
            version: '0.5.3',
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                }
            }
        }
    }
}
