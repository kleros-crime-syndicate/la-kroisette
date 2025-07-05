import { Network } from "hardhat/types";

export const isSkipped = async (network: Network, skip: boolean) => {
  if (skip) {
    console.error(`Error: incompatible network ${network.name} for this deployment script`);
    return true;
  }
  return false;
};
