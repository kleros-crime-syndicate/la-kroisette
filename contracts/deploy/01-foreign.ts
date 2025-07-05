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
      {{# answers }}
      {
        "title": "{{ title }}",
        "description": "{{ description }}",
        "id": "{{ id }}",
        "reserved": {{ reserved }}
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

const disputeTemplateMappings = `[
  {
    "type": "json",
    "value": {
      "question": "**Kleros Moderate:** Did the user, **degenape6** (ID: 1554345080), break the Telegram group, ***[Kleros Trading Group]()*** (ID: -1001151472172), ***[rules](https://cdn.kleros.link/ipfs/Qme3Qbj9rKUNHUe9vj9rqCLnTVUCWKy2YfveQF8HiuWQSu/Kleros%20Moderate%20Community%20Rules.pdf)*** due to conduct related to the ***[message](https://t.me/c/1151472172/116662)*** (***[backup](https://cdn.kleros.link/ipfs/QmVbFrZR1bcyQzZjvLyXwL9ekDxrqHERykdreRxXrw4nqg/animations_file_23.mp4)***)?",
      "type": "single-select",
      "answers": [
        {
          "title": "Refuse to Arbitrate or Invalid",
          "id": "0x00",
          "reserved": true
        },
        {
          "title": "Yes",
          "description": "The user broke the rules.",
          "id": "0x01",
          "reserved": false
        },
        {
          "title": "No",
          "description": "The user didnt break the rules.",
          "id": "0x02",
          "reserved": false
        },
        {
          "id": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
          "title": "Answered Too Soon",
          "reserved": true,
          "last": true
        }
      ],
      "questionId": "0xe2a3bd38e3ad4e22336ac35b221bbbdd808d716209f84014c7bc3bf62f8e3b39",
      "realityAddress": "0x14a6748192aBC6E10CA694Ae07bDd4327D6c7A51"
    },
    "seek": [
      "question",
      "type",
      "answers",
      "questionId",
      "realityAddress"
    ],
    "populate": [
      "question",
      "type",
      "answers",
      "questionId",
      "realityAddress"
    ]
  }
]`;

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

  const { klerosCore, disputeTemplateRegistry } = await getContractsEthers(ethers.provider, "testnet");
  const disputeTemplate = disputeTemplateFn(chainId, klerosCore.address as string);

  const homeNetwork = hre.config.networks[hre.network.companionNetworks.home];
  const endpointV2Deployment = await deployments.get('EndpointV2');
  
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

  await deploy("QuestionFormatter", {
    from: deployer,
    log: true,
  });
};

deploy.tags = ["Foreign"];
deploy.skip = async ({ network }) => {
  return isSkipped(network, network.name !== "arbitrum-sepolia");
};

export default deploy;
