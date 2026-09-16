import Foundation
import OSLog

/// Networking subgraph injected through ``DependencyContainer``.
///
/// CompositionRoot → AppEnvironment → DependencyContainer → NetworkingEnvironment
final class NetworkingEnvironment {
    let configuration: NetworkConfiguration
    let requestBuilder: RequestBuilder
    let client: NetworkClientBox
    let decoder: JSONResponseDecoder
    let uploadPipeline: UploadPipeline
    let downloadPipeline: DownloadPipeline
    let streaming: StreamingSupport
    let backgroundTransfers: BackgroundTransferSupport
    let reachability: ReachabilityMonitor
    let networkMonitor: NetworkMonitor
    let metricsRecorder: InMemoryRequestMetricsRecorder
    let errorMapper: NetworkErrorMapper

    init(
        configuration: NetworkConfiguration,
        requestBuilder: RequestBuilder,
        client: NetworkClientBox,
        decoder: JSONResponseDecoder,
        uploadPipeline: UploadPipeline,
        downloadPipeline: DownloadPipeline,
        streaming: StreamingSupport,
        backgroundTransfers: BackgroundTransferSupport,
        reachability: ReachabilityMonitor,
        networkMonitor: NetworkMonitor,
        metricsRecorder: InMemoryRequestMetricsRecorder,
        errorMapper: NetworkErrorMapper
    ) {
        self.configuration = configuration
        self.requestBuilder = requestBuilder
        self.client = client
        self.decoder = decoder
        self.uploadPipeline = uploadPipeline
        self.downloadPipeline = downloadPipeline
        self.streaming = streaming
        self.backgroundTransfers = backgroundTransfers
        self.reachability = reachability
        self.networkMonitor = networkMonitor
        self.metricsRecorder = metricsRecorder
        self.errorMapper = errorMapper
    }

    static func make(
        appConfiguration: AppConfiguration,
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil },
        startReachabilityMonitoring: Bool = true
    ) -> NetworkingEnvironment {
        let environment = StartupTrace.measure("NetworkingEnvironment.EnvironmentConfiguration") {
            EnvironmentConfiguration.make(
                for: appConfiguration.buildConfiguration,
                appConfiguration: appConfiguration
            )
        }
        let networkConfiguration = StartupTrace.measure("NetworkingEnvironment.NetworkConfiguration") {
            NetworkConfiguration.make(
                environment: environment,
                appDisplayName: appConfiguration.appDisplayName
            )
        }

        let reachability = StartupTrace.measure("NetworkingEnvironment.ReachabilityMonitor") {
            ReachabilityMonitor()
        }
        let metrics = InMemoryRequestMetricsRecorder()
        let metricsBox = RequestMetricsRecorderBox(recorder: metrics)
        let decoder = JSONResponseDecoder()
        let errorMapper = NetworkErrorMapper()
        let requestBuilder = StartupTrace.measure("NetworkingEnvironment.RequestBuilder") {
            RequestBuilder(configuration: networkConfiguration)
        }

        let session = StartupTrace.measure("NetworkingEnvironment.URLSession") {
            URLSession(
                configuration: networkConfiguration.makeURLSessionConfiguration(),
                delegate: URLSessionTaskMetricsCollector.shared,
                delegateQueue: nil
            )
        }

        let requestInterceptor = CompositeRequestInterceptor(
            interceptors: [
                LoggingRequestInterceptor(),
                SupabaseHeadersInterceptor(anonKey: environment.supabaseAnonKey),
                AuthenticationRequestInterceptor(accessTokenProvider: accessTokenProvider),
            ]
        )
        let responseInterceptor = CompositeResponseInterceptor(
            interceptors: [
                LoggingResponseInterceptor(),
            ]
        )

        let urlClient = StartupTrace.measure("NetworkingEnvironment.URLSessionNetworkClient") {
            URLSessionNetworkClient(
                session: session,
                requestInterceptor: requestInterceptor,
                responseInterceptor: responseInterceptor,
                retryPolicy: networkConfiguration.retryPolicy,
                errorMapper: errorMapper,
                decoder: decoder,
                metricsRecorder: metricsBox,
                reachability: reachability
            )
        }
        let clientBox = NetworkClientBox(client: urlClient)

        let networkMonitor = StartupTrace.measure("NetworkingEnvironment.NetworkMonitor") {
            let monitor = NetworkMonitor(reachability: reachability)
            if startReachabilityMonitoring {
                monitor.start()
            }
            return monitor
        }

        AppLog.networking.info(
            "NetworkingEnvironment ready (\(networkConfiguration.environment.apiEnvironment.rawValue, privacy: .public))"
        )

        return NetworkingEnvironment(
            configuration: networkConfiguration,
            requestBuilder: requestBuilder,
            client: clientBox,
            decoder: decoder,
            uploadPipeline: UploadPipeline(requestBuilder: requestBuilder),
            downloadPipeline: DownloadPipeline(session: session),
            streaming: StreamingSupport(client: clientBox),
            backgroundTransfers: BackgroundTransferSupport(configuration: networkConfiguration),
            reachability: reachability,
            networkMonitor: networkMonitor,
            metricsRecorder: metrics,
            errorMapper: errorMapper
        )
    }
}

/// Alias matching deliverable naming.
typealias ResponseDecoder = JSONResponseDecoder
