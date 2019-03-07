/* eslint-env mocha */
/* global artifacts, web3, contract, describe, it, beforeEach */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../helpers/constants.js')

const {
    upgradeContracts,
    deployContracts,
    confirmUpgrade
} = require('../../scripts/deploy/deploymentHandler')

const ConditionStoreManager = artifacts.require('ConditionStoreManager')

const ConditionStoreChangeFunctionSignature = artifacts.require('ConditionStoreChangeFunctionSignature')
const ConditionStoreChangeInStorage = artifacts.require('ConditionStoreChangeInStorage')
const ConditionStoreChangeInStorageAndLogic = artifacts.require('ConditionStoreChangeInStorageAndLogic')
const ConditionStoreExtraFunctionality = artifacts.require('ConditionStoreExtraFunctionality')
const ConditionStoreWithBug = artifacts.require('ConditionStoreWithBug')

contract('ConditionStoreManager', (accounts) => {
    let conditionStoreManagerAddress

    const verbose = false

    const deployer = accounts[0]
    const approver = accounts[2]
    const conditionCreater = accounts[5]

    beforeEach('Load wallet each time', async function() {
        const addressBook = await deployContracts(
            web3,
            artifacts,
            ['ConditionStoreManager'],
            true,
            verbose
        )

        conditionStoreManagerAddress = addressBook['ConditionStoreManager']
    })

    async function setupTest({
        conditionId = constants.bytes32.one,
        conditionType = constants.address.dummy
    } = {}) {
        const conditionStoreManager = await ConditionStoreManager.at(conditionStoreManagerAddress)
        return { conditionStoreManager, conditionId, conditionType }
    }

    describe('Test upgradability for ConditionStoreManager', () => {
        it('Should be possible to fix/add a bug', async () => {
            let { conditionId } = await setupTest()

            const taskBook = await upgradeContracts(
                web3,
                ['ConditionStoreWithBug:ConditionStoreManager'],
                verbose
            )

            await confirmUpgrade(
                web3,
                taskBook['ConditionStoreManager'],
                approver,
                verbose
            )

            const ConditionStoreWithBugInstance =
                await ConditionStoreWithBug.at(conditionStoreManagerAddress)

            // assert
            assert.strictEqual(
                (await ConditionStoreWithBugInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled,
                'condition should be fulfilled (according to bug)'
            )
        })

        it('Should be possible to change function signature', async () => {
            let { conditionId, conditionType } = await setupTest()

            const taskBook = await upgradeContracts(
                web3,
                ['ConditionStoreChangeFunctionSignature:ConditionStoreManager'],
                verbose
            )

            // init
            await confirmUpgrade(
                web3,
                taskBook['ConditionStoreManager'],
                approver,
                verbose
            )

            const ConditionStoreChangeFunctionSignatureInstance =
                await ConditionStoreChangeFunctionSignature.at(conditionStoreManagerAddress)

            await ConditionStoreChangeFunctionSignatureInstance.delegateCreateRole(
                conditionCreater,
                { from: deployer }
            )

            // assert
            assert.strictEqual(
                await ConditionStoreChangeFunctionSignatureInstance.getCreateRole(),
                conditionCreater,
                'Invalid create role!'
            )

            await ConditionStoreChangeFunctionSignatureInstance.createCondition(
                conditionId,
                conditionType,
                conditionCreater,
                { from: conditionCreater }
            )

            // assert
            assert.strictEqual(
                (await ConditionStoreChangeFunctionSignatureInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.unfulfilled,
                'condition should be unfulfilled'
            )
        })

        it('Should be possible to append storage variable(s) ', async () => {
            await setupTest()

            const taskBook = await upgradeContracts(
                web3,
                ['ConditionStoreChangeInStorage:ConditionStoreManager'],
                verbose
            )

            // init
            await confirmUpgrade(
                web3,
                taskBook['ConditionStoreManager'],
                approver,
                verbose
            )

            const ConditionStoreChangeInStorageInstance =
                await ConditionStoreChangeInStorage.at(conditionStoreManagerAddress)

            assert.strictEqual(
                (await ConditionStoreChangeInStorageInstance.conditionCount()).toNumber(),
                0
            )
        })

        it('Should be possible to append storage variables and change logic', async () => {
            let { conditionId, conditionType } = await setupTest()

            const taskBook = await upgradeContracts(
                web3,
                ['ConditionStoreChangeInStorageAndLogic:ConditionStoreManager'],
                verbose
            )

            // init
            await confirmUpgrade(
                web3,
                taskBook['ConditionStoreManager'],
                approver,
                verbose
            )

            const ConditionStoreChangeInStorageAndLogicInstance =
                await ConditionStoreChangeInStorageAndLogic.at(conditionStoreManagerAddress)

            await ConditionStoreChangeInStorageAndLogicInstance.delegateCreateRole(
                conditionCreater,
                { from: deployer }
            )

            assert.strictEqual(
                (await ConditionStoreChangeInStorageAndLogicInstance.conditionCount()).toNumber(),
                0
            )

            await ConditionStoreChangeInStorageAndLogicInstance.createCondition(
                conditionId,
                conditionType,
                conditionCreater,
                { from: conditionCreater }
            )

            assert.strictEqual(
                (await ConditionStoreChangeInStorageAndLogicInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.unfulfilled,
                'condition should be unfulfilled'
            )
        })

        it('Should be able to call new method added after upgrade is approved', async () => {
            await setupTest()

            const taskBook = await upgradeContracts(
                web3,
                ['ConditionStoreExtraFunctionality:ConditionStoreManager'],
                verbose
            )

            // init
            await confirmUpgrade(
                web3,
                taskBook['ConditionStoreManager'],
                approver,
                verbose
            )

            const ConditionStoreExtraFunctionalityInstance =
                await ConditionStoreExtraFunctionality.at(conditionStoreManagerAddress)

            // asset
            assert.strictEqual(
                await ConditionStoreExtraFunctionalityInstance.dummyFunction(),
                true
            )
        })
    })
})
