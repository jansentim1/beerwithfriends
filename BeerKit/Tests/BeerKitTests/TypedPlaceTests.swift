import Foundation
import Testing
@testable import BeerKit

@Suite struct TypedPlaceTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(TypedPlace.normalize("  Café De Zon,\n Amsterdam  ") == "Café De Zon, Amsterdam")
        #expect(TypedPlace.normalize("De   Zon") == "De Zon")
    }
    @Test func blankIsNotAPlace() {
        #expect(TypedPlace.normalize("") == nil)
        #expect(TypedPlace.normalize("   \n\t ") == nil)
        #expect(!TypedPlace.isValid("  "))
    }
    @Test func oneToSixtyIsAccepted() {
        #expect(TypedPlace.normalize("X") == "X")
        let sixty = String(repeating: "a", count: 60)
        #expect(TypedPlace.normalize(sixty) == sixty)
        #expect(TypedPlace.isValid(sixty))
    }
    @Test func overSixtyIsRefusedNotCut() {
        #expect(TypedPlace.normalize(String(repeating: "a", count: 61)) == nil)
    }
    @Test func lengthCountsUnicodeScalarsLikeTheRules() {
        // A flag is two scalars: 30 flags is 60 to Firestore, 31 is 62.
        let thirty = String(repeating: "🇳🇱", count: 30)
        #expect(TypedPlace.isValid(thirty))
        #expect(!TypedPlace.isValid(thirty + "🇳🇱"))
    }
    @Test func typingStopsAtTheCap() {
        #expect(TypedPlace.clampWhileTyping(String(repeating: "b", count: 75)).count == 60)
        #expect(TypedPlace.clampWhileTyping(String(repeating: "🇳🇱", count: 31)) == String(repeating: "🇳🇱", count: 30))
        #expect(TypedPlace.clampWhileTyping("Short") == "Short")
    }

    @Test @MainActor func typedPlaceGoesOnTheDrinkWithoutCoordinate() async {
        let svc = FakeBeerService()
        let places = FakePlaces(); places.place = "Somewhere GPS"; places.coordinate = Coordinate(latitude: 52.37, longitude: 4.895)
        let vm = HomeViewModel(service: svc, placeProvider: places, now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil, typedPlace: "  Café De Zon, Amsterdam ")
        #expect(svc.logged.first?.0.place == "Café De Zon, Amsterdam")
        #expect(svc.logged.first?.0.placeCoordinate == nil)
        #expect(vm.feed.first?.place == "Café De Zon, Amsterdam")
    }
    @Test @MainActor func blankTypedPlaceFallsBackToTheProvider() async {
        let svc = FakeBeerService()
        let places = FakePlaces(); places.place = "Café De Zon"
        let vm = HomeViewModel(service: svc, placeProvider: places, now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil, typedPlace: "   ")
        #expect(svc.logged.first?.0.place == "Café De Zon")
    }
}
