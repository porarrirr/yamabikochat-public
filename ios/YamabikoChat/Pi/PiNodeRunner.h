#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PiNodeRunnerErrorDomain;
typedef NS_ERROR_ENUM(PiNodeRunnerErrorDomain, PiNodeRunnerError) {
    PiNodeRunnerErrorAlreadyStarted = 1,
    PiNodeRunnerErrorPreparationFailed = 2,
};

@interface PiNodeRunner : NSObject
+ (BOOL)startEngineWithArguments:(NSArray<NSString *> *)arguments
                         error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(startEngine(arguments:));
/// Keeps the runtime listener open while the app is in the background, for work such as
/// App Intents that starts there without a foreground transition. Main thread only; balance
/// every hold with a release.
+ (void)holdListener;
+ (void)releaseListener;
#if DEBUG
+ (NSDictionary<NSString *, NSString *> *)engineDiagnostics;
#endif
@end

NS_ASSUME_NONNULL_END
