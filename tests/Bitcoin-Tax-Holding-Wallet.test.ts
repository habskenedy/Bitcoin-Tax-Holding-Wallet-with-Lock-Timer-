
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

const contractName = "Bitcoin-Tax-Holding-Wallet";

describe("Bitcoin Tax Holding Wallet - Core Functionality", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("allows deposits and tracks compliance", () => {
    const depositAmount = 1000000; // 1 STX in microSTX
    const unlockHeight = simnet.blockHeight + 144; // ~1 day
    
    const { result } = simnet.callPublicFn(
      contractName,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(unlockHeight)],
      address1
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Check balance was recorded
    const balanceResult = simnet.callReadOnlyFn(
      contractName,
      "get-balance",
      [Cl.principal(address1)],
      address1
    );
    expect(balanceResult.result).toBeOk(Cl.uint(depositAmount));
  });

  it("prevents deposits when already locked", () => {
    const depositAmount = 500000;
    const unlockHeight = simnet.blockHeight + 144;
    
    // First deposit should succeed
    simnet.callPublicFn(
      contractName,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(unlockHeight)],
      address2
    );
    
    // Second deposit should fail
    const { result } = simnet.callPublicFn(
      contractName,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(unlockHeight + 100)],
      address2
    );
    
    expect(result).toBeErr(Cl.uint(101)); // err-already-locked
  });
});

describe("Bitcoin Tax Holding Wallet - Tax Compliance Reporting", () => {
  it("records transaction history for deposits", () => {
    const depositAmount = 2000000;
    const unlockHeight = simnet.blockHeight + 200;
    
    // Make a deposit to trigger transaction recording
    simnet.callPublicFn(
      contractName,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(unlockHeight)],
      address1
    );
    
    // Check transaction was recorded (tx-id should be 1 for first transaction)
    const txResult = simnet.callReadOnlyFn(
      contractName,
      "get-transaction-history",
      [Cl.principal(address1), Cl.uint(1)],
      address1
    );
    
    // Transaction should be recorded with proper structure
    expect(txResult.result).toBeSome({
      "tx-type": "deposit",
      amount: depositAmount,
      "fees-paid": 0,
      "penalty-paid": 0
    });
  });

  it("generates annual tax summary", () => {
    const currentYear = Math.floor(simnet.blockHeight / 52560);
    
    // Get annual summary for current year
    const summaryResult = simnet.callReadOnlyFn(
      contractName,
      "get-annual-tax-summary",
      [Cl.principal(address1), Cl.uint(currentYear)],
      address1
    );
    
    // Should have summary data after deposit
    expect(summaryResult.result).toBeSome({
      "total-deposits": depositAmount,
      "total-withdrawals": 0,
      "total-fees-paid": 0,
      "total-penalties-paid": 0,
      "total-interest-earned": 0,
      "transaction-count": 1
    });
  });

  it("generates comprehensive tax compliance report", () => {
    const currentYear = Math.floor(simnet.blockHeight / 52560);
    
    const reportResult = simnet.callReadOnlyFn(
      contractName,
      "get-tax-compliance-report",
      [Cl.principal(address1), Cl.uint(currentYear)],
      address1
    );
    
    expect(reportResult.result).toBeOk();
  });

  it("allows owner to access compliance statistics", () => {
    const statsResult = simnet.callReadOnlyFn(
      contractName,
      "get-compliance-statistics",
      [],
      deployer
    );
    
    // Should return compliance statistics
    expect(statsResult.result).toBeOk({
      "total-transactions-recorded": expect.any(Number),
      "total-fees-collected": 0,
      "total-penalties-collected": 0,
      "current-tax-rate": 30,
      "current-interest-rate": 5
    });
  });

  it("prevents non-owners from accessing compliance statistics", () => {
    const statsResult = simnet.callReadOnlyFn(
      contractName,
      "get-compliance-statistics",
      [],
      address1
    );
    
    expect(statsResult.result).toBeErr(Cl.uint(100)); // err-owner-only
  });

  it("allows owner to export user transactions", () => {
    const exportResult = simnet.callReadOnlyFn(
      contractName,
      "export-user-transactions",
      [
        Cl.principal(address1),
        Cl.uint(1),
        Cl.uint(5)
      ],
      deployer
    );
    
    // Should return export metadata
    expect(exportResult.result).toBeOk({
      user: address1,
      "start-tx-id": 1,
      "end-tx-id": 5,
      "export-height": expect.any(Number)
    });
  });

  it("prevents non-owners from exporting user transactions", () => {
    const exportResult = simnet.callReadOnlyFn(
      contractName,
      "export-user-transactions",
      [
        Cl.principal(address1),
        Cl.uint(1),
        Cl.uint(5)
      ],
      address1
    );
    
    expect(exportResult.result).toBeErr(Cl.uint(100)); // err-owner-only
  });

  it("returns error for non-existent tax compliance data", () => {
    const futureYear = Math.floor(simnet.blockHeight / 52560) + 10;
    
    const reportResult = simnet.callReadOnlyFn(
      contractName,
      "get-tax-compliance-report",
      [Cl.principal(address2), Cl.uint(futureYear)],
      address2
    );
    
    expect(reportResult.result).toBeErr(Cl.uint(404));
  });
});
