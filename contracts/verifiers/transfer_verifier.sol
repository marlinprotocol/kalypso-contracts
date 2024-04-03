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
            10635980125175123040047008117497974270729500465307515900992196420983729029372,
            4561111046149768366187210726078806687495673627836037429532593158303266231966
        );
        vk.beta2 = Pairing.G2Point(
            [
                uint256(8834185769280868086257453506337298474281443410701390635282010951045363889009),
                19044604290113177657971952482889207881955167854230230159148212819144174265518
            ],
            [
                uint256(9380957610215948585877663490997127235607961371391449360027158141796681905751),
                3343936341862697616529892805610997193689954825857654780456276530766535815748
            ]
        );
        vk.gamma2 = Pairing.G2Point(
            [
                uint256(1024912775691380503343812723867986682106059308814642357360485186187709153736),
                17793837728125856783216886236271654784304886483065374177009672679100280243637
            ],
            [
                uint256(12087921604282247096625068398884866843880721079324874710275501840083602365113),
                3869274016033183041570438909413395135272533450129391688237458941855968183272
            ]
        );
        vk.delta2 = Pairing.G2Point(
            [
                uint256(2560537753094896948268298818641384221842717916769084396455166649216576603584),
                15619560235856906732352486429372469438492701621816292280495772679753148334164
            ],
            [
                uint256(19114212510584861874594539954238248497913355737632280045378414352309596015450),
                8908912922293406404990840265419262234781413279738442993235752092453018091211
            ]
        );
        vk.IC[0] = Pairing.G1Point(
            13394785184981711028422131407889889152954506812203907212864340313668556549721,
            11330118193436037745754550074270524504007562603800595159305549413295466410287
        );
        vk.IC[1] = Pairing.G1Point(
            16877941413177880261931584436517688155832551853685916970054883259548060482524,
            8789676210889373441416227955287869057785041704104013588669486738303350010170
        );
        vk.IC[2] = Pairing.G1Point(
            12112773953736667995084575149629266752487141356325096616380079554429360541330,
            399663197068194779412135453157090322686465666200006746488844195593436767989
        );
        vk.IC[3] = Pairing.G1Point(
            10490865638181153698036236647813574529599941183697950486605487801734460121356,
            12211369665991499670434391712514176476276581916991988326870881177527622895422
        );
        vk.IC[4] = Pairing.G1Point(
            14461465032969450622159410928688335499302827334676954054309007833327770277150,
            12311063961582451995715057038123810207913741925746234570064121827786668769098
        );
        vk.IC[5] = Pairing.G1Point(
            20306733269742243914272838547967838671969361932169793843473114094160840175215,
            4674221276739462234882732956657194053569542689486133944379973362648354511694
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
        return Pairing.pairing(Pairing.negate(_proof.A), _proof.B, vk.alfa1, vk.beta2, vk_x, vk.gamma2, _proof.C, vk.delta2);
    }
}
