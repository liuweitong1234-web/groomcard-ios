import UIKit

/// Shown instead of a browser error when the iPhone has no internet.
final class OfflineView: UIView {
    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.965, green: 0.969, blue: 0.961, alpha: 1)

        let paw = UILabel()
        paw.text = "🐾"
        paw.font = .systemFont(ofSize: 56)

        let title = UILabel()
        title.text = "You're offline"
        title.font = .boldSystemFont(ofSize: 22)
        title.textColor = UIColor(red: 0.11, green: 0.13, blue: 0.13, alpha: 1)

        let message = UILabel()
        message.text = "GroomCard needs the internet to load your diary. Check your Wi-Fi or mobile data, then try again."
        message.font = .systemFont(ofSize: 17)
        message.textColor = UIColor(red: 0.36, green: 0.40, blue: 0.40, alpha: 1)
        message.numberOfLines = 0
        message.textAlignment = .center

        let button = UIButton(type: .system)
        button.setTitle("Try again", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.backgroundColor = UIColor(red: 0.059, green: 0.463, blue: 0.431, alpha: 1)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [paw, title, message, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.setCustomSpacing(24, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            button.widthAnchor.constraint(equalToConstant: 180),
            button.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func retry() {
        onRetry?()
    }
}
