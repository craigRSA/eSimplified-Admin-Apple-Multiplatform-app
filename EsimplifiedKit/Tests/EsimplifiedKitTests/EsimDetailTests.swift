import XCTest
@testable import EsimplifiedKit

final class EsimDetailTests: XCTestCase {
    private func decodeEsim(_ json: String) throws -> EsimDetail {
        try JSONDecoder().decode(EsimDetail.self, from: Data(json.utf8))
    }

    // MARK: - Package display name (composed like the web packageName())

    func test_package_displayName_composed_from_country_allowance_days() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"123","packages":[
          {"status":"ACTIVE","package_country_name":"France","data_allowance_gigabytes":5,
           "time_allowance_days":30,"date_created_epoch":100,"package":{"name":"France 5GB"}}
        ]}
        """#)
        XCTAssertEqual(esim.packages.first?.displayName, "France 5 GB 30 Days")
    }

    func test_package_displayName_unlimited_via_negative_allowance() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"1","packages":[
          {"status":"ACTIVE","package_country_name":"Spain","data_allowance_gigabytes":-1,
           "time_allowance_days":1,"package":{"name":"Spain X"}}
        ]}
        """#)
        // -1 GB → Unlimited; 1 day → singular "Day".
        XCTAssertEqual(esim.packages.first?.displayName, "Spain Unlimited 1 Day")
    }

    func test_package_displayName_unlimited_via_nested_name() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"1","packages":[
          {"status":"ACTIVE","package_country_name":"USA","data_allowance_gigabytes":50,
           "time_allowance_days":7,"package":{"name":"USA Unlimited"}}
        ]}
        """#)
        XCTAssertEqual(esim.packages.first?.displayName, "USA Unlimited 7 Days")
    }

    func test_package_decodes_bytes_dates_and_used() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"1","packages":[
          {"status":"ACTIVE","package_country_name":"Italy","data_allowance_gigabytes":5,
           "time_allowance_days":30,"package":{"name":"Italy 5GB"},
           "data_allowance_bytes":5368709120,"data_usage_remaining_bytes":1073741824,
           "date_activated_epoch":1700000000,"supported_countries":["Italy","France"]}
        ]}
        """#)
        let pkg = try XCTUnwrap(esim.packages.first)
        XCTAssertEqual(pkg.dataUsedBytes, 4294967296)   // allowance − remaining
        XCTAssertEqual(pkg.dateActivatedEpoch, 1700000000)
        XCTAssertFalse(pkg.isUnlimited)
        XCTAssertEqual(pkg.supportedCountries, ["Italy", "France"])
    }

    func test_whitelist_decodes_lte_and_apn_flags() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"1","whitelist":[
          {"country":"France","operator":"Orange","data_allowed":true,
           "lte_support":"Yes","best_connectivity":"4G",
           "android_auto_apn":true,"ios_auto_apn":false}
        ]}
        """#)
        let w = try XCTUnwrap(esim.whitelist.first)
        XCTAssertEqual(w.lteSupport, "Yes")
        XCTAssertEqual(w.androidAutoApn, true)
        XCTAssertEqual(w.iosAutoApn, false)
    }

    func test_formatDataGB_thresholds_match_web() {
        XCTAssertEqual(EsimPackage.formatDataGB(-1), "Unlimited")
        XCTAssertEqual(EsimPackage.formatDataGB(0), "0 MB")
        XCTAssertEqual(EsimPackage.formatDataGB(Decimal(string: "0.5")!), "0 MB")
        XCTAssertEqual(EsimPackage.formatDataGB(1), "1 GB")
        XCTAssertEqual(EsimPackage.formatDataGB(20), "20 GB")
    }

    // MARK: - Sessions decode the byte-count "duration" + close_time_epoch

    func test_session_decodes_duration_bytes_and_close_time() throws {
        let list = try JSONDecoder().decode(EsimSessionList.self, from: Data(#"""
        {"results":[{"type":"data","country_name":"France","connect_time_epoch":1700000000,
                     "close_time_epoch":1700003600,"duration":1048576,"duration_gb":0.5}]}
        """#.utf8))
        let s = try XCTUnwrap(list.results.first)
        XCTAssertEqual(s.durationBytes, 1_048_576)
        XCTAssertEqual(s.closeTimeEpoch, 1_700_003_600)
        XCTAssertEqual(s.connectTimeEpoch, 1_700_000_000)
    }

    // MARK: - Active package selection (unchanged behavior, locked in)

    func test_activePackage_is_newest_active() throws {
        let esim = try decodeEsim(#"""
        {"iccid":"1","packages":[
          {"status":"ACTIVE","package_country_name":"A","data_allowance_gigabytes":1,"time_allowance_days":1,"date_created_epoch":100},
          {"status":"ACTIVE","package_country_name":"B","data_allowance_gigabytes":2,"time_allowance_days":2,"date_created_epoch":200},
          {"status":"EXPIRED","package_country_name":"C","data_allowance_gigabytes":3,"time_allowance_days":3,"date_created_epoch":300}
        ]}
        """#)
        XCTAssertEqual(esim.activePackage?.packageCountryName, "B")
    }
}
