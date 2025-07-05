import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { isSkipped } from "./utils";

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deploy } = deployments;

  // fallback to hardhat node signers on local network
  const deployer = (await getNamedAccounts()).deployer ?? (await hre.ethers.getSigners())[0].address;
  const chainId = Number(await getChainId());
  console.log("deploying to %s with deployer %s", hre.network.name, deployer);

  const realitioPolygon = "0x60573B8DcE539aE5bF9aD7932310668997ef0428";
  const foreignNetwork = hre.config.networks[hre.network.companionNetworks.foreign];
  const endpointV2Deployment = await hre.deployments.get('EndpointV2')
  
  await deploy("RealitioHomeProxyLZ", {
    from: deployer,
    args: [
      realitioPolygon,
      "", // Realitio metadata
      foreignNetwork.eid, // Foreign EID
      endpointV2Deployment.address, // LayerZero endpoint
    ],
    log: true,
  });
};

deploy.tags = ["Home"];
deploy.skip = async ({ network }) => {
  return isSkipped(network, network.name !== "sepolia");
};

export default deploy;
