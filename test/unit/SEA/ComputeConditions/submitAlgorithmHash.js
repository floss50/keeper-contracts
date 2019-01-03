/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, assert, contract, describe, it */

const ComputeConditions = artifacts.require('ComputeConditions.sol')
const ServiceExecutionAgreement = artifacts.require('ServiceExecutionAgreement.sol')

const utils = require('../../../helpers/utils.js')
const { initializeAgreement } = require('../../../helpers/initializeAgreement.js')

const web3 = utils.getWeb3()

contract('ComputeConditions', (accounts) => {
    let sea
    let computeConditions
    /* eslint-disable-next-line prefer-destructuring */
    const consumer = accounts[1]
    let contracts
    let fingerprints
    let dependenciesBits
    let valueHashes
    let timeoutValues
    let agreementId

    beforeEach(async () => {
        sea = await ServiceExecutionAgreement.new({ from: accounts[0] })
        computeConditions = await ComputeConditions.new(sea.address, { from: accounts[0] })
        contracts = [computeConditions.address]
        fingerprints = [utils.getSelector(web3, ComputeConditions, 'fulfillUpload')]
        dependenciesBits = [0]
        valueHashes = [utils.valueHash(['bool'], [true])]
        timeoutValues = [0]
        agreementId = utils.generateId()
    })

    async function initializeAgreementWithValues() {
        return initializeAgreement(
            sea,
            accounts[0],
            consumer,
            contracts,
            agreementId,
            fingerprints,
            valueHashes,
            timeoutValues,
            dependenciesBits)
    }

    describe('submitAlgorithmHash', () => {
        it('Should not submit when sender is not publisher', async () => {
            // act-assert
            try {
                await computeConditions.submitAlgorithmHash(agreementId, utils.emptyBytes32, { from: consumer })
            } catch (e) {
                assert.strictEqual(e.reason, 'Invalid publisher address')
                return
            }
            assert.fail('Expected revert not received')
        })

        it('Should submit', async () => {
            // arrange
            await initializeAgreementWithValues()

            // act
            const result = await computeConditions.submitAlgorithmHash(agreementId, utils.emptyBytes32, { from: accounts[0] })

            // assert
            utils.assertEmitted(result, 1, 'HashSubmitted')
        })

        it('Should re-submit when call submit twice', async () => {
            // arrange
            await initializeAgreementWithValues()
            await computeConditions.submitAlgorithmHash(agreementId, utils.emptyBytes32, { from: accounts[0] })

            // act
            const result = await computeConditions.submitAlgorithmHash(agreementId, utils.emptyBytes32, { from: accounts[0] })

            // assert
            utils.assertEmitted(result, 1, 'HashSubmitted')
            utils.assertEmitted(result, 1, 'ProofOfUploadInvalid')
        })
    })
})