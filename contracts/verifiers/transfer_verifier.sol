pragma solidity ^0.6.0;

library Pairing {
    uint256 constant PRIME_Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    struct G1Point {
        uint256 X;
        uint256 Y;
    }
    // Encoding of field elements is: X[0] * z + X[1]
    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }

    /*
     * @return The negation of p, i.e. p.plus(p.negate()) should be zero.
     */
    function negate(G1Point memory p) internal pure returns (G1Point memory) {
        // The prime q in the base field F_q for G1
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        } else {
            return G1Point(p.X, PRIME_Q - (p.Y % PRIME_Q));
        }
    }

    /*
     * @return r the sum of two points of G1
     */
    function plus(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 {
                invalid()
            }
        }
        require(success, "pairing-add-failed");
    }

    /*
     * @return r the product of a point on G1 and a scalar, i.e.
     *         p == p.scalar_mul(1) and p.plus(p) == p.scalar_mul(2) for all
     *         points p.
     */
    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 {
                invalid()
            }
        }
        require(success, "pairing-mul-failed");
    }

    /* @return The result of computing the pairing check
     *         e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
     *         For example,
     *         pairing([P1(), P1().negate()], [P2(), P2()]) should return true.
     */
    function pairing(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        G1Point memory c1,
        G2Point memory c2,
        G1Point memory d1,
        G2Point memory d2
    ) internal view returns (bool) {
        G1Point[4] memory p1 = [a1, b1, c1, d1];
        G2Point[4] memory p2 = [a2, b2, c2, d2];
        uint256 inputSize = 24;
        uint256[] memory input = new uint256[](inputSize);
        for (uint256 i = 0; i < 4; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }
        uint256[1] memory out;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 {
                invalid()
            }
        }
        require(success, "pairing-opcode-failed");
        return out[0] != 0;
    }
}

contract TransferVerifier {
    uint256 constant SNARK_SCALAR_FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant PRIME_Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    using Pairing for *;
    struct VerifyingKey {
        Pairing.G1Point alfa1;
        Pairing.G2Point beta2;
        Pairing.G2Point gamma2;
        Pairing.G2Point delta2;
        Pairing.G1Point[6] IC;
    }
    struct Proof {
        Pairing.G1Point A;
        Pairing.G2Point B;
        Pairing.G1Point C;
    }

    function verifyingKey() internal pure returns (VerifyingKey memory vk) {
        vk.alfa1 = Pairing.G1Point(
            3426398681869307216238004635196938062872335553575880022344349958233365637042,
            11092628405200207334723043345014479119556851550227705395913800620687498695561
        );
        vk.beta2 = Pairing.G2Point(
            [
                uint256(11019989146951473582029864985253393826565891035159871759431652073591124920674),
                10740073925763773907124072400465425321239946447343421112212169187417474077822
            ],
            [
                uint256(12429046889999856556416273990835084435106222859944463710940592709207826874568),
                9431789649983397777408298058306772589620385174115439588554619078999244899588
            ]
        );
        vk.gamma2 = Pairing.G2Point(
            [
                uint256(20071855736037225738300142081575283615764470467888751460660537356008570052812),
                2406802121726884542372917499211150657280514154671386836204834648811026917136
            ],
            [
                uint256(4597716334498686551078328980148740877209638516197018977048133168524067968674),
                17161934014288908492369304565070333311142743043050433890482272768234726237916
            ]
        );
        vk.delta2 = Pairing.G2Point(
            [
                uint256(14328503417236125810002613694096679239375068192784138599242048539806651540723),
                10534035423644593279226249282755002686898698419968046705030883836012334913209
            ],
            [
                uint256(7073629784325152690487340001805953732155631828586830602017111217424162198737),
                14013101799321384870339364378464624477032446595472830930433567599212068531795
            ]
        );
        vk.IC[0] = Pairing.G1Point(
            7919596649525844594761356958670933854964874934347595521826816123725808001372,
            1927024316177434261082064605736585667708876850573612727406496169758791832136
        );
        vk.IC[1] = Pairing.G1Point(
            15628147195006734448272610357514126669916231414481118557847823662224399899738,
            2494492726853242926932961240770969310035020543306392441684408164085317911839
        );
        vk.IC[2] = Pairing.G1Point(
            2726883123812963590706069397263659860852246356708760218913420715084798331550,
            3788166822968306518259210870109098276192465986467790028221701947371123242633
        );
        vk.IC[3] = Pairing.G1Point(
            1524052137640335683138690656888142149250526670289947725370555045324798221620,
            19935957416900299607045790756384708769890362644999608516265893224304176971623
        );
        vk.IC[4] = Pairing.G1Point(
            17519069767494295222462734981505121032256324858915739583976784461992729787084,
            14077901351399766975975327175860884110108509466297671826547528199066984889551
        );
        vk.IC[5] = Pairing.G1Point(
            5757476419947538637277502716972885742096730786930277138150935635910054401070,
            2198170185847892864124708282522171183077472731314941107034546526310025918042
        );
    }

    /*
     * @returns Whether the proof is valid given the hardcoded verifying key
     *          above and the public inputs
     */
    function verifyProof(uint256[5] memory input, uint256[8] memory p) public view returns (bool) {
        // Make sure that each element in the proof is less than the prime q
        for (uint8 i = 0; i < p.length; i++) {
            require(p[i] < PRIME_Q, "verifier-proof-element-gte-prime-q");
        }
        Proof memory _proof;
        _proof.A = Pairing.G1Point(p[0], p[1]);
        _proof.B = Pairing.G2Point([p[3], p[2]], [p[5], p[4]]);
        _proof.C = Pairing.G1Point(p[6], p[7]);
        VerifyingKey memory vk = verifyingKey();
        // Compute the linear combination vk_x
        Pairing.G1Point memory vk_x = Pairing.G1Point(0, 0);
        vk_x = Pairing.plus(vk_x, vk.IC[0]);
        // Make sure that every input is less than the snark scalar field
        for (uint256 i = 0; i < input.length; i++) {
            require(input[i] < SNARK_SCALAR_FIELD, "verifier-gte-snark-scalar-field");
            vk_x = Pairing.plus(vk_x, Pairing.scalar_mul(vk.IC[i + 1], input[i]));
        }
        return
            Pairing.pairing(
                Pairing.negate(_proof.A),
                _proof.B,
                vk.alfa1,
                vk.beta2,
                vk_x,
                vk.gamma2,
                _proof.C,
                vk.delta2
            );
    }
}
