#import <Foundation/Foundation.h>
#import <MumbleKit/MKCertificate.h>

// This is just a temporary tool to test MKCertificate
int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSData *data = [NSData dataWithContentsOfFile:@"Certificates.cer"];
    MKCertificate *cert = [MKCertificate certificateWithCertificate:data privateKey:nil];
    if ([cert hasCertificate]) {
        NSLog(@"digest = %@", [cert hexDigest]);
    }

    [pool release];
    return 0;
}
