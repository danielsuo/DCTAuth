//
//  DCTAuthSecureStorage.m
//  DCTAuth
//
//  Created by Daniel Tull on 16.02.2013.
//  Copyright (c) 2013 Daniel Tull. All rights reserved.
//

#import "_DCTAuthSecureStorage.h"
#import "_DCTAuthPasswordProvider.h"
#import <CommonCrypto/CommonCryptor.h>
#import <Security/Security.h>

NSString *const DCTAuthSecureStorageKeys = @"DCTAuthSecureStorageKeys";

@interface DCTAuthSecureStorage ()
@property (nonatomic, strong) NSMutableDictionary *dictionary;
@property (nonatomic, readwrite) NSData *encryptedData;
@property (nonatomic, weak) DCTAuthAccount *account;
@end

@implementation DCTAuthSecureStorage

- (id)init {
	self = [self init];
	if (!self) return nil;
	_dictionary = [NSMutableDictionary new];
	return self;
}

- (void)setObject:(NSString *)value forKey:(NSString *)key {
	[self.dictionary setObject:value forKey:key];
}

- (NSString *)objectForKey:(NSString *)key {
	NSString *object = [self.dictionary objectForKey:key];
	if (object) return object;
	return [[self class] secureValueForKey:key account:self.account];
}

#pragma mark - Encryption

- (NSData *)decryptData:(NSData *)data withPassword:(NSString *)key {
	// 'key' should be 32 bytes for AES256, will be null-padded otherwise
	char keyPtr[kCCKeySizeAES256+1]; // room for terminator (unused)
	bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)

	// fetch key data
	[key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];

	NSUInteger dataLength = [data length];

	//See the doc: For block ciphers, the output size will always be less than or
	//equal to the input size plus the size of one block.
	//That's why we need to add the size of one block here
	size_t bufferSize = dataLength + kCCBlockSizeAES128;
	void *buffer = malloc(bufferSize);

	size_t numBytesDecrypted = 0;
	CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
										  keyPtr, kCCKeySizeAES256,
										  NULL /* initialization vector (optional) */,
										  [data bytes], dataLength, /* input */
										  buffer, bufferSize, /* output */
										  &numBytesDecrypted);

	if (cryptStatus == kCCSuccess) {
		//the returned NSData takes ownership of the buffer and will free it on deallocation
		return [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
	}

	free(buffer); //free the buffer;
	return nil;
}

- (NSData *)encryptData:(NSData *)data withPassword:(NSString *)key {
	
	// 'key' should be 32 bytes for AES256, will be null-padded otherwise
	char keyPtr[kCCKeySizeAES256+1]; // room for terminator (unused)
	bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)

	// fetch key data
	[key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];

	NSUInteger dataLength = [data length];

	//See the doc: For block ciphers, the output size will always be less than or
	//equal to the input size plus the size of one block.
	//That's why we need to add the size of one block here
	size_t bufferSize = dataLength + kCCBlockSizeAES128;
	void *buffer = malloc(bufferSize);

	size_t numBytesEncrypted = 0;
	CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
										  keyPtr, kCCKeySizeAES256,
										  NULL /* initialization vector (optional) */,
										  [data bytes], dataLength, /* input */
										  buffer, bufferSize, /* output */
										  &numBytesEncrypted);
	if (cryptStatus == kCCSuccess) {
		//the returned NSData takes ownership of the buffer and will free it on deallocation
		return [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
	}

	free(buffer); //free the buffer;
	return nil;
}

#pragma mark - Keychain

+ (void)setSecureValue:(NSString *)value forKey:(NSString *)key account:(DCTAuthAccount *)account {
	if (!value) return;
	if (!key) return;

	[self removeSecureValueForKey:key account:account];

	NSMutableDictionary *query = [self queryForKey:key account:account];
	[query setObject:[value dataUsingEncoding:NSUTF8StringEncoding] forKey:(__bridge id)kSecValueData];
#ifdef TARGET_OS_IPHONE
	[query setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock forKey:(__bridge id)kSecAttrAccessible];
#endif
	SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

+ (NSString *)secureValueForKey:(NSString *)key account:(DCTAuthAccount *)account {
	if (!key) return nil;

	NSMutableDictionary *query = [self queryForKey:key account:account];
	[query setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
	[query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
	CFTypeRef result = NULL;
	SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (!result) return nil;
	return [[NSString alloc] initWithData:(__bridge_transfer NSData *)result encoding:NSUTF8StringEncoding];
}

+ (void)removeSecureValueForKey:(NSString *)key account:(DCTAuthAccount *)account {
	NSMutableDictionary *query = [self queryForKey:key account:account];
    SecItemDelete((__bridge CFDictionaryRef)query);
}

+ (NSMutableDictionary *)queryForKey:(NSString *)key account:(DCTAuthAccount *)account {
	NSMutableDictionary *query = [NSMutableDictionary new];
    [query setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
	[query setObject:[NSString stringWithFormat:@"DCTAuth:%@", account.identifier] forKey:(__bridge id)kSecAttrService];
	if (key) [query setObject:key forKey:(__bridge id)kSecAttrAccount];
	return query;
}

@end





@implementation DCTAuthSecureStorage (Private)
@dynamic encryptedData;

- (id)initWithEncryptedData:(NSData *)data {
	self = [self init];
	if (!self) return nil;
	_encryptedData = [data copy];
	return self;
}

+ (void)removeAllKeychainItemsForAccount:(DCTAuthAccount *)account {
	[self removeSecureValueForKey:nil account:account];
}

- (void)encryptWithAccount:(DCTAuthAccount *)account {

	NSString *password = [[_DCTAuthPasswordProvider sharedPasswordProvider] passwordForAccount:account];

	if (password.length == 0) {
		[self.dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
			[[self class] setSecureValue:object forKey:key account:account];
		}];
	} else {
		NSData *dictionaryArchive = [NSKeyedArchiver archivedDataWithRootObject:self.dictionary];
		self.encryptedData = [self encryptData:dictionaryArchive withPassword:password];
	}

	self.dictionary = nil;
}

- (void)decryptWithAccount:(DCTAuthAccount *)account {

	self.account = account;

	if (!self.encryptedData) return;

	NSString *password = [[_DCTAuthPasswordProvider sharedPasswordProvider] passwordForAccount:account];

	if (password.length == 0) return;

	NSData *dictionaryArchive = [self decryptData:self.encryptedData withPassword:password];
	self.dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:dictionaryArchive];
}

@end