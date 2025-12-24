import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

/**
 * Deploy VNĐ₮ Stablecoin System
 * Contracts: VNDT Token, VNDTEngine, VNDTOracle, VNDTStaking, VNDTDEX, VNDTRateController
 */
const deployVNDT: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  console.log("\n========== Deploying VNĐ₮ Stablecoin System ==========");
  console.log(`Deployer: ${deployer}`);
  console.log(`Network: ${hre.network.name}\n`);

  const deployerNonce = await hre.ethers.provider.getTransactionCount(deployer);

  // Calculate future addresses
  const futureStakingAddress = hre.ethers.getCreateAddress({
    from: deployer,
    nonce: deployerNonce + 4,
  });

  const futureEngineAddress = hre.ethers.getCreateAddress({
    from: deployer,
    nonce: deployerNonce + 5,
  });

  console.log("📍 Predicted Addresses:");
  console.log(`   Staking: ${futureStakingAddress}`);
  console.log(`   Engine: ${futureEngineAddress}\n`);

  // 1. Deploy RateController
  console.log("1️⃣  Deploying VNDTRateController...");
  const rateControllerDeploy = await deploy("VNDTRateController", {
    from: deployer,
    args: [futureEngineAddress, futureStakingAddress],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${rateControllerDeploy.address}\n`);
  const rateController = await hre.ethers.getContract<Contract>("VNDTRateController", deployer);

  // 2. Deploy VNDT Token
  console.log("2️⃣  Deploying VNDT Token...");
  const vndtDeploy = await deploy("VNDT", {
    from: deployer,
    args: [futureEngineAddress, futureStakingAddress],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${vndtDeploy.address}\n`);
  const vndt = await hre.ethers.getContract<Contract>("VNDT", deployer);

  // 3. Deploy DEX
  console.log("3️⃣  Deploying VNDTDEX...");
  const dexDeploy = await deploy("VNDTDEX", {
    from: deployer,
    args: [vndt.target],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${dexDeploy.address}\n`);
  const dex = await hre.ethers.getContract<Contract>("VNDTDEX", deployer);

  // 4. Deploy Oracle
  console.log("4️⃣  Deploying VNDTOracle...");
  const ethPrice = hre.ethers.parseEther("2500"); // 1 ETH = 2500 VND (example rate)
  const oracleDeploy = await deploy("VNDTOracle", {
    from: deployer,
    args: [ethPrice],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${oracleDeploy.address}`);
  console.log(`   ETH Price: ${hre.ethers.formatEther(ethPrice)} VND\n`);
  const oracle = await hre.ethers.getContract<Contract>("VNDTOracle", deployer);

  // 5. Deploy Staking
  console.log("5️⃣  Deploying VNDTStaking...");
  const stakingDeploy = await deploy("VNDTStaking", {
    from: deployer,
    args: [vndt.target, futureEngineAddress, rateController.target],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${stakingDeploy.address}\n`);
  const staking = await hre.ethers.getContract<Contract>("VNDTStaking", deployer);

  // 6. Deploy Engine
  console.log("6️⃣  Deploying VNDTEngine...");
  const engineDeploy = await deploy("VNDTEngine", {
    from: deployer,
    args: [oracle.target, vndt.target, staking.target, rateController.target],
    log: true,
  });
  console.log(`   ✅ Deployed at: ${engineDeploy.address}\n`);
  const engine = await hre.ethers.getContract<Contract>("VNDTEngine", deployer);

  // Verify predicted address
  if (engine.target !== futureEngineAddress) {
    throw new Error("Engine address does not match predicted address!");
  }

  console.log("========== VNĐ₮ Stablecoin System Deployed Successfully! ==========\n");
  console.log("📋 Deployment Summary:");
  console.log(`   VNDT Token: ${vndt.target}`);
  console.log(`   VNDTEngine: ${engine.target}`);
  console.log(`   VNDTOracle: ${oracle.target}`);
  console.log(`   VNDTStaking: ${staking.target}`);
  console.log(`   VNDTDEX: ${dex.target}`);
  console.log(`   VNDTRateController: ${rateController.target}\n`);

  // Save deployment info
  const deploymentInfo = {
    network: hre.network.name,
    deployer,
    timestamp: new Date().toISOString(),
    contracts: {
      vndt: vndt.target,
      engine: engine.target,
      oracle: oracle.target,
      staking: staking.target,
      dex: dex.target,
      rateController: rateController.target,
    },
  };

  console.log("✅ Deployment complete!");
};

deployVNDT.tags = ["VNDT"];
export default deployVNDT;
