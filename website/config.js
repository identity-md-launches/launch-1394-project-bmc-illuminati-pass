// bmc-pass site configuration. Fill PASS_ADDRESS after mainnet deployment (owner's responsibility).
window.BMC_PASS_CONFIG = {
  CHAIN_ID: 1, // Ethereum mainnet
  CHAIN_NAME: "Ethereum Mainnet",
  EXPLORER: "https://etherscan.io",
  BMC_ADDRESS: "0x38224239f2BDae357D47cb864BC533d7f72dF961",
  PASS_ADDRESS: "", // <-- set to the deployed BMCIlluminatiPass address
  IPFS_GATEWAY: "https://ipfs.io/ipfs/",
  GENESIS_PRICE: 1000000n * 10n ** 18n,
  MYSTERY_PRICE: 350000n * 10n ** 18n,
};
