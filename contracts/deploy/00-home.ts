import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { isSkipped } from "./utils";

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId } = hre;
  const { deploy } = deployments;

  // fallback to hardhat node signers on local network
  const deployer = (await getNamedAccounts()).deployer ?? (await hre.ethers.getSigners())[0].address;
  const chainId = Number(await getChainId());
  console.log("deploying to %s with deployer %s", hre.network.name, deployer);

  const realitioSepolia = "0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA";
  const foreignNetwork = hre.config.networks[hre.network.companionNetworks.foreign];
  const endpointV2Deployment = await deployments.get('EndpointV2');
  
  await deploy("RealitioHomeProxyLZ", {
    from: deployer,
    args: [
      realitioSepolia,
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
