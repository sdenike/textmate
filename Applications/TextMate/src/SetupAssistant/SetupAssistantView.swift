// Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift
import SwiftUI

public enum TMSetupAssistantStep: Int, CaseIterable {
	case welcome = 0
	case appearance = 1
	case bundles = 2

	var title: String {
		switch self {
			case .welcome:    return "Welcome to TextMate"
			case .appearance: return "Appearance"
			case .bundles:    return "Bundles"
		}
	}
}
