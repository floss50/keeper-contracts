/* eslint-env mocha */
/* global artifacts, assert, contract, describe, it, beforeEach, before */
const ZeppelinHelper = require('../../helpers/ZeppelinHelper.js')
const OceanToken = artifacts.require('OceanToken.sol')

contract('OceanToken', (accounts) => {
    let token
    let zos
    let spender

    before('restore zos state before all tests', async () => {
        zos = new ZeppelinHelper('OceanToken')
        await zos.restoreState(accounts[9])
        /* eslint-disable-next-line */
        spender = accounts[1]
    })

    describe('transfer', () => {
        beforeEach('mint tokens before each test', async () => {
            await zos.initialize(accounts[0], false)
            token = await OceanToken.at(zos.getProxyAddress('OceanToken'))
            await token.mint(spender, 1000)
        })

        it('Should transfer', async () => {
            // act
            await token.transfer(accounts[2], 100, { from: spender })

            // assert
            const balance = await token.balanceOf(accounts[2])
            assert.strictEqual(balance.toNumber(), 100)
        })

        it('Should not transfer to empty address', async () => {
            // act-assert
            try {
                await token.transfer(0x0, 100, { from: spender })
            } catch (e) {
                assert.strictEqual(e.reason, 'invalid address')
                return
            }
            assert.fail('Expected revert not received')
        })
    })
})