import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { isSkipped } from "./utils";
import { getContractsEthers } from "@kleros/kleros-v2-contracts";

const disputeTemplateFn = (chainId: number, arbitratorAddress: string) => `{
    "title": "A reality.eth question",
    "description": "A reality.eth question has been raised to arbitration.",
    "question": "{{ question }}",
    "type": "{{ type }}",
    "answers": [
      {
        "title": "Answered Too Soon",
        "description": "Answered Too Soon.",
      },
      {{# answers }}
      {
          "title": "{{ title }}",
          "description": "{{ description }}",
      }{{^ last }},{{/ last }}
      {{/ answers }}
    ],
    "policyURI": "/ipfs/QmZ5XaV2RVgBADq5qMpbuEwgCuPZdRgCeu8rhGtJWLV6yz",
    "frontendUrl": "https://reality.eth.limo/app/#!/question/{{ realityAddress }}-{{ questionId }}",
    "arbitratorChainID": "${chainId}",
    "arbitratorAddress": "${arbitratorAddress}",
    "category": "Oracle",
    "lang": "en_US",
    "specification": "KIP99",
    "version": "1.0"
}`;

// General court, 1 jurors
const extraData =
  "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001";

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deploy } = deployments;

  // fallback to hardhat node signers on local network
  const deployer = (await getNamedAccounts()).deployer ?? (await hre.ethers.getSigners())[0].address;
  const chainId = Number(await getChainId());
  console.log("deploying to %s with deployer %s", hre.network.name, deployer);

  const weth = await deployments.get("WETH");

  const { klerosCore, disputeTemplateRegistry } = await getContractsEthers(ethers.provider, "mainnetNeo");
  const disputeTemplate = disputeTemplateFn(chainId, klerosCore.address as string);
  const disputeTemplateMappings = "TODO";

  const homeNetwork = hre.config.networks[hre.network.companionNetworks.home];
  const endpointV2Deployment = await hre.deployments.get('EndpointV2')
  
  await deploy("RealitioForeignProxyLZ", {
    from: deployer,
    args: [
      weth.address,
      klerosCore.address,
      extraData,
      disputeTemplateRegistry.address,
      disputeTemplate,
      disputeTemplateMappings,
      homeNetwork.eid, // Home EID
      endpointV2Deployment.address, // LayerZero endpoint
    ],
    log: true,
  });
};

deploy.tags = ["Foreign"];
deploy.skip = async ({ network }) => {
  return isSkipped(network, network.name !== "arbitrum-sepolia");
};

export default deploy;
