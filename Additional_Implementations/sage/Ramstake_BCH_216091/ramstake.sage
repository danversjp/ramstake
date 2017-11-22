load("codec_bch.sage")
from csprng import csprng
from binascii import hexlify
from CompactFIPS202 import SHA3_256, SHAKE256

RAMSTAKE_SEED_LENGTH = 32
RAMSTAKE_KEY_LENGTH = 32

RAMSTAKE_MODULUS_BITSIZE = 216091
RAMSTAKE_ADDITIVE_SPARSITY = 238
RAMSTAKE_MULTIPLICATIVE_SPARSITY = 18

RAMSTAKE_DECAPSULATION_FAILURE = -1
RAMSTAKE_INTEGRITY_FAILURE = -2
RAMSTAKE_ULONG_LENGTH = 8
RAMSTAKE_ENCAPS_RANDOM_BYTES = RAMSTAKE_ULONG_LENGTH * (RAMSTAKE_ADDITIVE_SPARSITY + RAMSTAKE_MULTIPLICATIVE_SPARSITY)
RAMSTAKE_KEYGEN_RANDOM_BYTES = RAMSTAKE_ULONG_LENGTH * (RAMSTAKE_ADDITIVE_SPARSITY + RAMSTAKE_MULTIPLICATIVE_SPARSITY) + RAMSTAKE_SEED_LENGTH

class ramstake_public_key:
    def __init__( self ):
        self.c = 0

class ramstake_secret_key:
    def __init__( self ):
        self.a = 0
        self.b = 0

class ramstake_ciphertext:
    def __init__( self ):
        self.d = 0
        self.e = bytearray([])
        self.h = bytearray([])

def ramstake_sample_sparse_integer( buff, sparsity ):
    integer = 0
    for i in range(0, sparsity):
        uli = sum([256^j * buff[RAMSTAKE_ULONG_LENGTH*i+j] for j in range(0,RAMSTAKE_ULONG_LENGTH)])
        difference = 2^(uli % RAMSTAKE_MODULUS_BITSIZE)
        integer += difference

    return integer

def ramstake_generate_g( seed ):
    data = SHAKE256(bytearray(seed), ceil(RAMSTAKE_MODULUS_BITSIZE/8))

    g = 0
    for i in range(0,len(data)):
        g = 256*g + int(data[i])

    return g

def ramstake_keygen( random_seed, kat ):
    # get csprng from seed
    rng = csprng()
    rng.seed(random_seed)

    if kat >= 1:
        print "\n# ramstake_keygen"
        print "seed:", hexlify(random_seed)

    # expand randomness
    randomness_index = 0
    randomness = rng.generate(RAMSTAKE_KEYGEN_RANDOM_BYTES)

    # grab seed for g
    pk = ramstake_public_key()
    pk.seed = randomness[randomness_index:(randomness_index+RAMSTAKE_SEED_LENGTH)]
    randomness_index += RAMSTAKE_SEED_LENGTH
    g = ramstake_generate_g(pk.seed)
    if kat >= 1:
        print "seed for generating g:", hexlify(pk.seed)
    if kat >= 3:
        print "g:", g

    # sample secret integers a and b
    sk = ramstake_secret_key()
    sk.seed = copy(random_seed)
    # sample sparse secret integers
    buff = randomness[randomness_index:(randomness_index + RAMSTAKE_MULTIPLICATIVE_SPARSITY*RAMSTAKE_ULONG_LENGTH)]
    randomness_index += RAMSTAKE_MULTIPLICATIVE_SPARSITY * RAMSTAKE_ULONG_LENGTH
    sk.a = ramstake_sample_sparse_integer(buff, RAMSTAKE_MULTIPLICATIVE_SPARSITY)
    buff = randomness[randomness_index:(randomness_index + RAMSTAKE_ADDITIVE_SPARSITY*RAMSTAKE_ULONG_LENGTH)]
    randomness_index += RAMSTAKE_ADDITIVE_SPARSITY * RAMSTAKE_ULONG_LENGTH
    sk.b = ramstake_sample_sparse_integer(buff, RAMSTAKE_ADDITIVE_SPARSITY)
    if kat >= 3:
        print "Sampled short and sparse integers a and b."
        print "a:", sk.a
        print "b:", sk.b

    # obtain modulus
    p = 2^RAMSTAKE_MODULUS_BITSIZE - 1

    # compute c = ag + b mod p
    pk.c = (g * sk.a + sk.b) % p
    if kat >= 3:
        print "Computed c = ag + b mod p."
        print "c:", pk.c

    return sk, pk

def ramstake_encaps( random_seed, pk, kat ):
    # get csprng from seed
    rng = csprng()
    rng.seed(random_seed)

    if kat >= 1:
        print "\n# ramstake_encaps"
        print "seed:", hexlify(random_seed)

    # expand randomness
    randomness_index = 0
    randomness = SHAKE256(random_seed, RAMSTAKE_KEYGEN_RANDOM_BYTES)

    # sample secret integers a and b
    buff = randomness[randomness_index:(randomness_index + RAMSTAKE_MULTIPLICATIVE_SPARSITY*RAMSTAKE_ULONG_LENGTH)]
    randomness_index += RAMSTAKE_MULTIPLICATIVE_SPARSITY * RAMSTAKE_ULONG_LENGTH
    a = ramstake_sample_sparse_integer(buff, RAMSTAKE_MULTIPLICATIVE_SPARSITY)
    buff = randomness[randomness_index:(randomness_index + RAMSTAKE_ADDITIVE_SPARSITY*RAMSTAKE_ULONG_LENGTH)]
    randomness_index += RAMSTAKE_ADDITIVE_SPARSITY * RAMSTAKE_ULONG_LENGTH
    b = ramstake_sample_sparse_integer(buff, RAMSTAKE_ADDITIVE_SPARSITY)
    if kat >= 3:
        print "Sampled short and sparse integers a and b."
        print "a:", a
        print "b:", b

    # recreate g from pk seed
    g = ramstake_generate_g(pk.seed)
    if kat >= 3:
        print "Recreated g from public key seed."
        print "g:", g

    # obtain modulus
    p = 2^RAMSTAKE_MODULUS_BITSIZE - 1

    # compute d = ag + b mod p
    c = ramstake_ciphertext()
    c.d = (a*g + b) % p
    if kat >= 3:
        print "Computed d = ag + b mod p."
        print "d:", c.d

    # compute s = ac mod p
    s = (a*pk.c) % p
    if kat >= 3:
        print "Computed noisy shared secret integer s = ac mod p."
        print "pk.c:", pk.c
        print "p:", p
        print "s:", s

    # draw appropriate number of most significant bytes from s
    string = hex(s)
    if len(string) % 2 == 1:
        string = '0' + string
    c.e = bytearray(string[0:(2*floor(RAMSTAKE_MODULUS_BITSIZE/8)*8)].decode("hex"))
    if kat >= 3:
        print "Drew most significant", floor(RAMSTAKE_MODULUS_BITSIZE/8)*8, "bytes from s:", hexlify(c.e)

    # encode randomness seed
    codec = CODEC(256, floor(RAMSTAKE_MODULUS_BITSIZE/8)*8)
    data = codec.encode(random_seed)
    if kat >= 2:
        print "Encoded randomness using repetition of", codec.repetitions, "codewords of length", floor(codec.n / codec.repetitions)
    if kat >= 3:
        print "codeword sequence: ", hexlify(data)

    # apply otp to codeword sequence
    for i in range(0, len(data)):
        c.e[i] = c.e[i] ^^ data[i]
    if kat >= 3:
        print "Applied one-time pad to repetition codeword."
        print "data:", hexlify(c.e)

    # add hash of seed to ciphertext
    c.h = SHA3_256(random_seed)
    if kat >= 1:
        print "Hash of seed in ciphertext:", hexlify(c.h)

    # obtain symmetric key as k = H(randomness || pk)
    string = hex(pk.c + 255*2^RAMSTAKE_MODULUS_BITSIZE)
    if len(string)%2 == 1:
        string = '0'+string
    string = randomness + bytearray(string.decode("hex"))
    key = SHA3_256(string)
    if kat >= 1:
        print "Hashed s into key:", hexlify(key)
        if kat >= 3:
            print "From s:", (((s+b)%p) + 255*2^RAMSTAKE_MODULUS_BITSIZE)

    return c, key

def ramstake_decaps( c, sk, kat ):
    # recreate pk
    pk = ramstake_public_key()
    rng = csprng()
    rng.seed(sk.seed)
    pk.seed = rng.generate(RAMSTAKE_SEED_LENGTH)
    if kat >= 1:
        print "\n# ramstake_decaps"
        print "secret key seed:", hexlify(sk.seed)
        print "Recreated public key seed for g:", hexlify(pk.seed)

    # recreate g
    g = ramstake_generate_g(pk.seed)

    # obtain modulus
    p = 2^RAMSTAKE_MODULUS_BITSIZE - 1

    # compute s = da mod p
    s = (c.d * sk.a) % p
    if kat >= 3:
        print "Computed noisy shared secret integer s = da mod p."
        print "s:", s
        print "from sk.a:", sk.a

    # draw appropriate number of bytes from s
    string = hex(s)
    if len(string) % 2 == 1:
        string = '0' + string
    word = bytearray(string[0:(2*floor(RAMSTAKE_MODULUS_BITSIZE/8)*8)].decode("hex"))
    if kat >= 3:
        print "Drew most significant", floor(RAMSTAKE_MODULUS_BITSIZE/8)*8, "bytes from s:", hexlify(word)

    # undo OTP
    for i in range(0, len(word)):
        word[i] = word[i] ^^ c.e[i]
    if kat >= 3:
        print "Undid one-time pad:", hexlify(word)

    # try to decode
    codec = CODEC(256, floor(RAMSTAKE_MODULUS_BITSIZE/8)*8)
    decoded = codec.decode(word, c.h)
    if decoded == bytearray([0]*len(decoded)):
        if kat >= 1:
            print "Received word was not decodable."
        return RAMSTAKE_DECAPSULATION_FAILURE

    # re-create ciphertext
    pk.c = (sk.a * g + sk.b) % p
    rec, key = ramstake_encaps(bytearray(decoded), pk, 0)
    if kat >= 1:
        print "Re-encapsulating ciphertext from transmitted seed."
        print "seed:", hexlify(bytearray(decoded))
    if kat >= 3:
        print "d:", rec.d
        print "e:", hexlify(rec.e)

    if rec.d != c.d or rec.e != c.e or rec.h != c.h:
        if rec.d != c.d:
            print "recreated d =/= ciphertext d"
        if rec.e != c.e:
            print "recreated e =/= ciphertext e"
        if rec.h != c.h:
            print "recreated h =/= ciphertext h"
        return RAMSTAKE_INTEGRITY_FAILURE

    return key

def ramstake_export_secret_key( sk ):
    ret = copy(sk.seed)
    hexa = hex(sk.a)
    hexb = hex(sk.b)
    if len(hexa) % 2 == 1:
        hexa = "0" + hexa
    if len(hexb) % 2 == 1:
        hexb = "0" + hexb
    bytesa = bytearray(list(hexa.decode("hex")))
    bytesb = bytearray(list(hexb.decode("hex")))
    while len(bytesa) <= RAMSTAKE_MODULUS_BITSIZE/8:
        bytesa.append(0)
    while len(bytesb) <= RAMSTAKE_MODULUS_BITSIZE/8:
        bytesb.append(0)
    ret.extend(bytesa)
    ret.extend(bytesb)
    return ret

