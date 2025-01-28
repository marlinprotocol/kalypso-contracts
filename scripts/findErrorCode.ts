import { ErrorFragment } from "ethers";
import * as fs from "fs";
import * as path from "path";

// TODO: Later convert this into a command line argument
const errorCode = "0xe2517d3f";

// Define the path to the artifacts directory
const artifactsDir = path.join(__dirname, "../artifacts/contracts");

// Interface for the result
interface Result {
    found: boolean;
    errorName?: string;
    contractName?: string;
    selector?: string;
}

// Function to compute the error signature using ethers.js ErrorFragment
const findErrorSelectorInAbi = (
    contractName: string,
    allFragments: any[],
    selector: string
): Result => {
    const errorFragments = allFragments.filter((a) => a.type === "error");

    for (const errorFragment of errorFragments) {
        try {
            const ef = ErrorFragment.from(errorFragment);

            if (ef.selector === selector) {
                console.log(
                    `Contract: ${contractName}, Error: ${ef.name}, Selector: ${ef.selector}`
                );
                return { found: true, errorName: ef.name, contractName, selector };
            }
        } catch (error) {
            console.error(
                `Error processing fragment in contract ${contractName}:`,
                error
            );
        }
    }

    return { found: false };
};

// Function to recursively get all JSON files in a directory
const getAllJsonFiles = (dir: string, files_?: string[]): string[] => {
    files_ = files_ || [];
    const files = fs.readdirSync(dir);
    for (const file of files) {
        const name = path.join(dir, file);
        if (fs.statSync(name).isDirectory()) {
            getAllJsonFiles(name, files_);
        } else if (name.endsWith(".json")) {
            files_.push(name);
        }
    }
    return files_;
};

// Main function to execute the scanning
const main = () => {
    // Get all ABI JSON files
    const abiFiles = getAllJsonFiles(artifactsDir);

    if (abiFiles.length === 0) {
        console.log("No ABI files found in the artifacts directory.");
        return;
    }

    let anyFound = false;

    // Iterate over each ABI file
    abiFiles.forEach((filePath) => {
        try {
            const fileContent = fs.readFileSync(filePath, "utf8");
            const parsedJson = JSON.parse(fileContent);

            // Extract ABI and contract name
            const abi = parsedJson.abi;
            const contractName = parsedJson.contractName || path.basename(filePath, ".json");

            if (!abi || !Array.isArray(abi)) {
                return;
            }

            // Search for the error selector in the ABI
            const result = findErrorSelectorInAbi(contractName, abi, errorCode);

            if (result.found) {
                anyFound = true;
            }
        } catch (error) {
            console.error(`Error processing file ${filePath}:`, error);
        }
    });

    if (!anyFound) {
        console.log(`No matching error selector (${errorCode}) found in any ABI.`);
    }
};

// Execute the main function
main();
