module.exports = {
    rpc: {
        host:"127.0.0.1",
        port:8543
    },

    networks: {
        test: {
            host: "127.0.0.1",
            port: 8543,
            network_id: "*",
            from: "854c55d65bf425569263d5fae98d01bd7a96fd3c", // predefined account address (geth-keystore) 
            "gas":17592186044415,
            "gasPrice":1
        }
    },
    compilers: {
        solc: {
            settings: {
                optimizer: {
                    enabled: true,
runs: 200
                },
            }
        }
    }
};
