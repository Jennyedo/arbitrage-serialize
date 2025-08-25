import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.5/index.ts';
import { assertEquals } from 'https://deno.land/std@0.166.0/testing/asserts.ts';

Clarinet.test({
  name: "Create Arbitrage Strategy",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const strategiesBlock = chain.mineBlock([
      Tx.contractCall(
        'arbitrage-tracker', 
        'create-arbitrage-strategy', 
        [
          types.ascii('Eth-Btc Cross-Chain'),
          types.utf8('Low-risk arbitrage between Ethereum and Bitcoin chains'),
          types.ascii('ethereum'),
          types.ascii('bitcoin'),
          types.uint(2),  // Medium frequency
          types.uint(1),  // Low risk
          types.uint(1000)  // Max allocation
        ],
        deployer.address
      )
    ]);

    assertEquals(strategiesBlock.height, 2);
    assertEquals(strategiesBlock.receipts.length, 1);
    strategiesBlock.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "Execute Arbitrage Strategy",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const strategiesBlock = chain.mineBlock([
      Tx.contractCall(
        'arbitrage-tracker', 
        'create-arbitrage-strategy', 
        [
          types.ascii('Eth-Btc Cross-Chain'),
          types.utf8('Low-risk arbitrage between Ethereum and Bitcoin chains'),
          types.ascii('ethereum'),
          types.ascii('bitcoin'),
          types.uint(2),  // Medium frequency
          types.uint(1),  // Low risk
          types.uint(1000)  // Max allocation
        ],
        deployer.address
      )
    ]);

    const executionBlock = chain.mineBlock([
      Tx.contractCall(
        'arbitrage-tracker',
        'execute-arbitrage-strategy',
        [
          types.uint(1),
          types.uint(500),
          types.utf8('Successful cross-chain arbitrage')
        ],
        deployer.address
      )
    ]);

    assertEquals(executionBlock.height, 3);
    assertEquals(executionBlock.receipts.length, 1);
    executionBlock.receipts[0].result.expectOk().expectUint(1);
  }
});