import { Wallet, utils, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import fs from "fs"; 
import * as secrets from "../secrets.json"; 

// Get private key from the environment variable
const PRIVATE_KEY: string = secrets.privateKey;

interface DependencyAbis {
    wETH: any;
    vault: any;
    master: any;
    classicFactory: any;
    stableFactory: any;
    router: any;
    feeManager: any;
    feeRecipient: any;
    feeRegistry: any;
    forwardRegistry: any;
    classicPool: any;
}

interface DependencyContracts {
    wETH: string;
    vault: string;
    master: string;
    classicFactory: string;
    stableFactory: string;
    router: string;
    feeManager: string;
    feeRecipient: string;
    feeRegistry: string;
    forwardRegistry: string;
}

interface DeployedContracts {
    HandsToken: string;
    Hands: string;
    Bankroll: string;
    Staking: string;
    Affiliate: string;
}

interface DeployedAbis {
    HandsToken: any;
    Hands: any;
    Bankroll: any;
    Staking: any;
    Affiliate: any;
}

const fetchDependencyAbis = async (): Promise<DependencyAbis> => {
    const wETHFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/WETH.sol/WETH.json");
    const vaultFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/vault/SyncSwapVault.sol/SyncSwapVault.json");
    const masterFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/master/SyncSwapPoolMaster.sol/SyncSwapPoolMaster.json");
    const classicFactoryFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/pool/classic/SyncSwapClassicPoolFactory.sol/SyncSwapClassicPoolFactory.json");
    const stableFactoryFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/pool/stable/SyncSwapStablePoolFactory.sol/SyncSwapStablePoolFactory.json");
    const routerFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/SyncSwapRouter.sol/SyncSwapRouter.json");
    const feeManagerFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/master/SyncSwapFeeManager.sol/SyncSwapFeeManager.json");
    const feeRecipientFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/master/SyncSwapFeeRecipient.sol/SyncSwapFeeRecipient.json");
    const feeRegistryFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/master/FeeRegistry.sol/FeeRegistry.json");
    const forwardRegistryFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/master/ForwarderRegistry.sol/ForwarderRegistry.json");
    const classicPoolFile = fs.readFileSync("./syncswap-contracts/artifacts-zk/contracts/pool/classic/SyncSwapClassicPool.sol/SyncSwapClassicPool.json");

    //make sure all files are loaded
    if(!wETHFile || !vaultFile || !masterFile || !classicFactoryFile || !stableFactoryFile || !routerFile || !feeManagerFile || !feeRecipientFile || !feeRegistryFile || !forwardRegistryFile || !classicPoolFile) {
        throw new Error("Please run `yarn deploy:local` first");
    }

    const wETH = JSON.parse(wETHFile.toString()).abi;
    const vault = JSON.parse(vaultFile.toString()).abi;
    const master = JSON.parse(masterFile.toString()).abi;
    const classicFactory = JSON.parse(classicFactoryFile.toString()).abi;
    const stableFactory = JSON.parse(stableFactoryFile.toString()).abi;
    const router = JSON.parse(routerFile.toString()).abi;
    const feeManager = JSON.parse(feeManagerFile.toString()).abi;
    const feeRecipient = JSON.parse(feeRecipientFile.toString()).abi;
    const feeRegistry = JSON.parse(feeRegistryFile.toString()).abi;
    const forwardRegistry = JSON.parse(forwardRegistryFile.toString()).abi;
    const classicPool = JSON.parse(classicPoolFile.toString()).abi;

    //make sure all files are parsed
    if(!wETH || !vault || !master || !classicFactory || !stableFactory || !router || !feeManager || !feeRecipient || !feeRegistry || !forwardRegistry || !classicPool) {
        throw new Error("Please run `yarn deploy:local` first");
    }

    return {
        wETH,
        vault,
        master,
        classicFactory,
        stableFactory,
        router,
        feeManager,
        feeRecipient,
        feeRegistry,
        forwardRegistry,
        classicPool
    }
}

const fetchDependencyContracts = async (): Promise<DependencyContracts> => {
    const file = fs.readFileSync("./local-dependency-contracts.json");

    if(!file) {
        throw new Error("Please run `yarn deploy:local` first");
    }

    const contracts: DependencyContracts = JSON.parse(file.toString());

    if(!contracts) {
        throw new Error("Please run `yarn deploy:local` first");
    }

    return contracts;
}


const setLocalContractFile = async (
        dependencyContracts: DependencyContracts,
        dependencyAbis: DependencyAbis,
        deployedContracts: DeployedContracts,
        deployedAbis: DeployedAbis,
    ) => {
    const file = {
        dependencyContracts,
        dependencyAbis,
        deployedContracts,
        deployedAbis
    };

    fs.writeFileSync("./local-contracts.json", JSON.stringify(file, null, 4));
}

function waitForPoolCreatedEvent(contract: any): Promise<string> {
    return new Promise((resolve, reject) => {
        // Event listener
        contract.on('PoolCreated', (token0: any, token1: any, pool: any) => {
            console.log(`PoolCreated event received: token0: ${token0}, token1: ${token1}, pool: ${pool}`);
            contract.off('PoolCreated'); // Stop listening after the event is received
            resolve(pool);  // Resolve the promise with pool address
        });

        // Error handling
        setTimeout(() => {
            reject(new Error('Timeout: PoolCreated event not received'));
        }, 60000);  // 60 second timeout, adjust as needed
    });
}

export default async function (hre: HardhatRuntimeEnvironment) {
    console.log(`Running deploy script for the Hands and Bankroll contracts`);

    //Fetch wallet and deployer
    const l2Provider = new Provider("http://localhost:3050");
    const wallet = new Wallet(PRIVATE_KEY, l2Provider);
    const deployer = new Deployer(hre, wallet);


    //dependency contracts
    const dependencyContracts = await fetchDependencyContracts();
    console.log(dependencyContracts);

    //dependency abis
    const dependencyAbis = await fetchDependencyAbis();
    //console.log(dependencyAbis);



    //DEPLOY HANDS TOKEN

    // Load the artifact of the HandsToken contract you want to deploy.
    const handsTokenArtifact = await deployer.loadArtifact("HandsToken");

    // Set the premintReceiver, premintAmount, and supplyCap according to your requirements.
    const premintReceiver = wallet.address;
    const premintAmount = ethers.utils.parseUnits("1000000", 18);
    const supplyCap = ethers.utils.parseUnits("10000000", 18);

    // Deploy the HandsToken contract
    const handsTokenContract = await deployer.deploy(handsTokenArtifact, [premintReceiver, premintAmount, supplyCap]);
    const handsTokenContractAddress = handsTokenContract.address;
    console.log(`HandsToken was deployed to ${handsTokenContractAddress}`);


    
    //DEPLOY AFFILIATE CONTRACT

    // Load the artifact of the Affiliate contract you want to deploy.
    const affiliateArtifact = await deployer.loadArtifact("Affiliate");

    // Deploy Affiliate contract
    const affiliateContract = await deployer.deploy(affiliateArtifact);

    // Show the Affiliate contract info
    const affiliateContractAddress = affiliateContract.address;
    console.log(`Affiliate was deployed to ${affiliateContractAddress}`);



    //DEPLOY STAKING CONTRACT

    // Load the artifact of the Staking contract you want to deploy.
    const stakingArtifact = await deployer.loadArtifact("Staking");

    // Estimate Staking contract deployment fee
    const stakingDeploymentFee = await deployer.estimateDeployFee(stakingArtifact, [handsTokenContractAddress]);

    const parsedStakingFee = ethers.utils.formatEther(stakingDeploymentFee.toString());
    console.log(`The Staking deployment is estimated to cost ${parsedStakingFee} ETH`);

    // Deploy Staking contract, passing the addresses of the deployed HandsToken and Bankroll contracts to the constructor
    const stakingContract = await deployer.deploy(stakingArtifact, [handsTokenContractAddress]);

    // Show the Staking contract info
    const stakingContractAddress = stakingContract.address;
    console.log(`Staking was deployed to ${stakingContractAddress}`);
    




    //DEPLOY BANKROLL CONTRACT

    // Load the artifact of the Bankroll contract you want to deploy.
    const bankrollArtifact = await deployer.loadArtifact("Bankroll");

    // Deploy Bankroll contract
    const bankrollContract = await deployer.deploy(bankrollArtifact, [affiliateContractAddress, stakingContractAddress]);

    // Show the Bankroll contract info
    const bankrollContractAddress = bankrollContract.address;
    console.log(`Bankroll was deployed to ${bankrollContractAddress}`);

    //set banking contract for both affiliate and staking
    const setBankForAffiliateTx = await affiliateContract.setBankContract(bankrollContractAddress);
    console.log(`Affiliate contract setBankContract tx: ${setBankForAffiliateTx.hash}`);
    const setBankForStakingTx = await stakingContract.setBankContract(bankrollContractAddress);
    console.log(`Staking contract setBankContract tx: ${setBankForStakingTx.hash}`);




    //DEPLOY HANDS CONTRACT

    // Load the artifact of the Hands contract you want to deploy.
    const handsArtifact = await deployer.loadArtifact("Hands");

    // Estimate Hands contract deployment fee
    const handsDeploymentFee = await deployer.estimateDeployFee(handsArtifact, [bankrollContractAddress]);

    const parsedHandsFee = ethers.utils.formatEther(handsDeploymentFee.toString());
    console.log(`The Hands deployment is estimated to cost ${parsedHandsFee} ETH`);

    // Deploy Hands contract, passing the address of the deployed Bankroll contract to the constructor
    const handsContract = await deployer.deploy(handsArtifact, [bankrollContractAddress]);

    // Show the Hands contract info
    const handsContractAddress = handsContract.address;
    console.log(`Hands was deployed to ${handsContractAddress}`);




    //DEPLOYMENT FILE   
    //create new json file with all the contract addresses
    const deployedContracts: DeployedContracts = {
        HandsToken: handsTokenContractAddress,
        Bankroll: bankrollContractAddress,
        Staking: stakingContractAddress,
        Hands: handsContractAddress,
        Affiliate: affiliateContractAddress,
    };

    const deployedAbis: DeployedAbis = {
        HandsToken: handsTokenArtifact.abi,
        Bankroll: bankrollArtifact.abi,
        Staking: stakingArtifact.abi,
        Hands: handsArtifact.abi,
        Affiliate: affiliateArtifact.abi,
    };

    setLocalContractFile(
        dependencyContracts,
        dependencyAbis,
        deployedContracts,
        deployedAbis
    );

}

